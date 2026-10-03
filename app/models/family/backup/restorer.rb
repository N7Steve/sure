require "bcrypt"
require "set"

class Family::Backup::Restorer
  def initialize(family, content, import: nil, import_session: nil)
    @family = family
    @content = content
    @import = import
    @import_session = import_session
    @id_map = {}
    @targets = {}
    @reused = Set.new
    @uploaded_blobs = []
  end

  def validate!
    rows = @content.each_line.reject { |line| line.strip.empty? }.map { |line| JSON.parse(line) }
    fail_backup("Backup rows must be JSON objects") unless rows.all? { |row| row.is_a?(Hash) }
    manifests = rows.select { |row| row["type"] == "BackupManifest" }
    fail_backup("Missing or duplicate backup manifest") unless manifests.one?
    @manifest = manifests.first.fetch("data")
    fail_backup("Invalid backup manifest") unless @manifest.is_a?(Hash)
    fail_backup("Unsupported backup version") unless @manifest["version"] == Family::Backup::VERSION
    @records = rows.select { |row| row["type"] == "BackupRecord" }
    @attachments = rows.select { |row| row["type"] == "BackupAttachment" }
    payload = rows.select { |row| row["type"].in?(%w[BackupRecord BackupAttachment]) }.map(&:to_json).join("\n")
    fail_backup("Backup checksum mismatch") unless Digest::SHA256.hexdigest(payload) == @manifest["sha256"]
    @source_records = {}
    @records.each do |row|
      data = row.fetch("data")
      fail_backup("Invalid backup record") unless data.is_a?(Hash)
      model = Family::Backup.models[data["model"]]
      fail_backup("Unsupported backup model #{data['model']}") unless model
      attrs = data.fetch("attributes")
      fail_backup("Invalid attributes for #{model.name}") unless attrs.is_a?(Hash) && attrs["id"].present?
      fail_backup("Duplicate source id #{model.name}:#{attrs['id']}") if @source_records.key?(source_key(model.name, attrs["id"]))
      fail_backup("Unknown attributes for #{model.name}") if (attrs.keys - model.column_names).any?
      fail_backup("Excluded attributes for #{model.name}") if (attrs.keys & (Family::Backup::EXCLUDED_ATTRIBUTES[model.name] || [])).any?
      if attrs["family_id"].present? && attrs["family_id"] != @manifest["family_id"]
        fail_backup("#{model.name} belongs to another family")
      end
      if model == Merchant
        fail_backup("Invalid merchant type") unless attrs["type"].in?(%w[FamilyMerchant ProviderMerchant])
        fail_backup("Family merchant is missing family") if attrs["type"] == "FamilyMerchant" && attrs["family_id"].blank?
      elsif model.column_names.include?("family_id")
        fail_backup("#{model.name} is missing family") if attrs["family_id"].blank?
      end
      if model == Import
        fail_backup("Invalid import type") unless attrs["type"].in?(Import::TYPES)
      elsif model == Import::Mapping
        allowed = %w[Import::AccountMapping Import::AccountTypeMapping Import::CategoryMapping Import::TagMapping Import::MerchantMapping]
        fail_backup("Invalid import mapping type") unless attrs["type"].in?(allowed)
      elsif model == User
        fail_backup("Invalid family member role") unless attrs["role"].in?(User.roles.keys)
      end
      @source_records[source_key(model.name, attrs["id"])] = data
    end
    families = @records.select { |row| row.dig("data", "model") == "Family" }
    fail_backup("Backup must contain its family") unless families.one? && families.first.dig("data", "attributes", "id") == @manifest["family_id"]
    @records.each do |row|
      data = row["data"]
      references(data).each do |field, target_name|
        source_id = data["attributes"][field]
        next if source_id.blank?
        target = @source_records[source_key(target_name, source_id)]
        fail_backup("Missing #{target_name} reference: #{data['model']}.#{field}") unless target && target["model"] == target_name
      end
    end
    @attachments.each do |row|
      data = row["data"]
      fail_backup("Invalid backup attachment") unless data.is_a?(Hash)
      owner = @source_records[source_key(data["model"], data["record_id"])]
      fail_backup("Attachment owner is missing") unless owner && owner["model"] == data["model"]
      model = Family::Backup.attachment_model(data["model"], owner["attributes"])
      fail_backup("Unknown attachment name") unless model.attachment_reflections.key?(data["name"])
      bytes = Base64.strict_decode64(data.fetch("content"))
      fail_backup("Attachment checksum mismatch") unless bytes.bytesize == data["byte_size"] && Digest::MD5.base64digest(bytes) == data["checksum"]
    end
    self
  rescue JSON::ParserError, KeyError, ArgumentError, TypeError => error
    fail_backup("Invalid backup: #{error.message}")
  end

  def counts
    @records.each_with_object(Hash.new(0)) do |row, counts|
      name = row.dig("data", "model")
      counts[Family::Backup.models.fetch(name).table_name] += 1 unless name == "Family"
    end
  end

  def warnings
    documents_with_originals = @attachments.filter_map do |row|
      data = row["data"]
      data["record_id"] if data["model"] == "FamilyDocument" && data["name"] == "file"
    end.to_set
    @records.filter_map do |row|
      data = row["data"]
      attrs = data["attributes"]
      next unless data["model"] == "FamilyDocument" && attrs["file_size"].to_i.positive? && !documents_with_originals.include?(attrs["id"])

      { code: "source_original_unavailable", message: "The source did not retain the original file for #{attrs['filename']}.", details: { source_id: attrs["id"], filename: attrs["filename"] } }
    end
  end

  def restore!
    validate!
    replay = @import&.summary&.dig("backup_restore")
    if replay && replay["sha256"] == @manifest["sha256"]
      @id_map = replay.fetch("id_map")
      @records.each do |row|
        data = row["data"]
        key = record_key(data)
        @reused.add(key)
        @targets[key] = User.find(@id_map.fetch(key)) if data["model"] == "User"
      end
      verify_records!
      verify_attachments!
      return result
    end

    @family.with_lock(requires_new: true) do
      # Restoring into existing financial data would merge two different states.
      fail_backup("Restore a full backup into a family without financial data") if @family.accounts.exists? || @family.goals.exists? || @family.scheduled_payments.exists? || @family.budgets.exists? || @family.recurring_transactions.exists? || @family.rules.exists?
      allocate_targets!
      clear_unused_taxonomy!
      insert_records!
      restore_attachments!
      verify_records!
      persist_source_mappings!
      @import&.update!(summary: { "backup_restore" => { "sha256" => @manifest["sha256"], "id_map" => @id_map } })
    end
    result
  rescue StandardError
    # Object storage is outside the SQL transaction. Purge only blobs created by
    # this attempt, after the database has rolled back.
    @uploaded_blobs.each do |blob|
      blob.service.delete(blob.key)
    end
    raise
  end

  private
    def persist_source_mappings!
      return unless @import_session

      @records.each do |row|
        data = row["data"]
        name = data["model"]
        next unless ImportSourceMapping::SOURCE_TYPES.include?(name)
        old_id = data.dig("attributes", "id")
        mapping = @import_session.source_mappings.find_or_initialize_by(family: @family, source_type: name, source_id: old_id)
        mapping.target = Family::Backup.models.fetch(name).find(@id_map.fetch(source_key(name, old_id)))
        mapping.save!
      end
    end

    def fail_backup(message)
      raise Family::Backup::InvalidBackupError, message
    end

    def source_key(model, id)
      "#{model}:#{id}"
    end

    def record_key(data)
      source_key(data["model"], data.dig("attributes", "id"))
    end

    def references(data)
      model = Family::Backup.models.fetch(data["model"])
      attrs = data["attributes"]
      excluded = Family::Backup::EXCLUDED_ATTRIBUTES[model.name] || []
      initial = attrs.key?("family_id") ? { "family_id" => "Family" } : {}
      model.reflect_on_all_associations(:belongs_to).each_with_object(initial) do |association, refs|
        field = association.foreign_key
        next if excluded.include?(field) || !attrs.key?(field)
        target_name = association.polymorphic? ? attrs[association.foreign_type] : association.class_name
        next if target_name.blank? && attrs[field].blank?
        target_name = "Merchant" if target_name.in?(%w[FamilyMerchant ProviderMerchant])
        fail_backup("Unsupported reference #{model.name}.#{field}") unless Family::Backup::MODEL_NAMES.include?(target_name)
        refs[field] = target_name
      end
    end

    def allocate_targets!
      @records.each do |row|
        data = row["data"]
        attrs = data["attributes"]
        model = Family::Backup.models.fetch(data["model"])
        existing = existing_record(model, attrs)
        key = record_key(data)
        @id_map[key] = existing&.id || SecureRandom.uuid
        @targets[key] = existing if existing
        @reused.add(key) if existing
      end
    end

    def existing_record(model, attrs)
      case model.name
      when "Family"
        @family
      when "User"
        user = @family.users.find_by(email: attrs["email"])
        if !user && attrs["role"].in?(%w[admin super_admin]) && !@admin_mapped
          user = @family.users.where(role: %w[admin super_admin]).order(:created_at, :id).first
        end
        @admin_mapped = true if user&.admin?
        fail_backup("User #{attrs['email']} already belongs to another family") if !user && User.where(email: attrs["email"]).exists?
        user
      when "Category", "Tag"
        model.where(family_id: @family.id).find_by(name: attrs["name"])
      when "Merchant"
        if attrs["type"] == "ProviderMerchant"
          ProviderMerchant.find_by(source: attrs["source"], name: attrs["name"])
        else
          @family.merchants.find_by(name: attrs["name"])
        end
      when "Security"
        Security.where("upper(ticker) = ? AND COALESCE(upper(exchange_operating_mic), '') = ?", attrs["ticker"].upcase, attrs["exchange_operating_mic"].to_s.upcase).first
      when "Security::Price"
        Security::Price.find_by(security_id: @id_map[source_key("Security", attrs["security_id"])], date: attrs["date"], currency: attrs["currency"])
      when "ExchangeRate", "ExchangeRatePair"
        model.find_by(attrs.slice("from_currency", "to_currency", "date"))
      end
    end

    def remap_json(value, hint: nil)
      case value
      when String
        return @id_map.fetch(source_key(hint, value), value) if hint
        @json_id_map ||= @source_records.values.group_by { |data| data.dig("attributes", "id") }
          .filter_map { |id, records| [ id, @id_map.fetch(record_key(records.first)) ] if records.one? }.to_h
        @json_id_map.fetch(value, value)
      when Array then value.map { |item| remap_json(item, hint: hint) }
      when Hash
        value.to_h do |key, item|
          child_hint = key == "id" ? hint : reference_hint(key)
          [ key, remap_json(item, hint: child_hint) ]
        end
      else value
      end
    end

    def reference_hint(field)
      explicit = { "pledge_id" => "GoalPledge", "owner_id" => "User", "viewer_id" => "User", "target_account_id" => "Account", "default_account_id" => "Account" }
      explicit[field] || field.to_s.delete_suffix("_ids").delete_suffix("_id").camelize.presence_in(Family::Backup::MODEL_NAMES)
    end

    def target_attributes(data)
      model = Family::Backup.models.fetch(data["model"])
      attrs = data["attributes"].deep_dup
      attrs.each do |field, value|
        next if field.start_with?("raw_") || field == "sanitized_parser_output"
        if model.columns_hash.fetch(field).type.in?(%i[json jsonb]) || value.is_a?(Array)
          attrs[field] = remap_json(value, hint: reference_hint(field))
        end
      end
      if data["model"] == "DataEnrichment"
        attrs["value"] = remap_json(data.dig("attributes", "value"), hint: reference_hint(attrs["attribute_name"]))
      end
      attrs["id"] = @id_map.fetch(record_key(data))
      references(data).each do |field, target_name|
        attrs[field] = @id_map.fetch(source_key(target_name, attrs[field])) if attrs[field].present?
      end
      existing = @targets[record_key(data)]
      if data["model"] == "User"
        attrs["role"] = existing ? existing.role : (attrs["role"] == "super_admin" ? "admin" : attrs["role"])
        attrs["email"] = existing.email if existing
        attrs["password_digest"] = BCrypt::Password.create(SecureRandom.hex(32)).to_s unless existing
      end
      if data["model"] == "Rule::Action" && attrs["action_type"] == "set_transaction_tags"
        attrs["value"] = data["attributes"]["value"].to_s.split(",").map { |id| @id_map.fetch(source_key("Tag", id), id) }.join(",")
      end
      if data["model"].in?(%w[Rule::Action Rule::Condition])
        operand_types = { "set_transaction_category" => "Category", "set_transaction_merchant" => "Merchant", "transaction_category" => "Category", "transaction_merchant" => "Merchant", "transaction_tag" => "Tag", "transaction_account" => "Account" }
        hint = operand_types[attrs["action_type"] || attrs["condition_type"]]
        attrs["value"] = @id_map.fetch(source_key(hint, attrs["value"]), attrs["value"]) if hint
      end
      attrs
    end

    def clear_unused_taxonomy!
      # Onboarding creates taxonomy before the user can upload a backup. Remove
      # only unused target records absent from the snapshot in this empty family.
      [ Category, Tag, FamilyMerchant ].each do |model|
        kept_ids = @targets.values.select { |record| record.is_a?(model) }.map(&:id)
        model.where(family_id: @family.id).where.not(id: kept_ids).destroy_all
      end
    end

    def insert_records!
      pending = @records.reject { |row| @reused.include?(record_key(row["data"])) }
      inserted = @reused.dup
      until pending.empty?
        ready, pending = pending.partition do |row|
          data = row["data"]
          model = Family::Backup.models.fetch(data["model"])
          references(data).all? do |field, target_name|
            source_id = data["attributes"][field]
            source_id.blank? || model.columns_hash.fetch(field).null || inserted.include?(source_key(target_name, source_id))
          end
        end
        fail_backup("Circular required references in backup") if ready.empty?
        ready.each do |row|
          data = row["data"]
          model = Family::Backup.models.fetch(data["model"])
          attrs = target_attributes(data)
          references(data).each do |field, target_name|
            source_id = data["attributes"][field]
            attrs[field] = nil if source_id.present? && !inserted.include?(source_key(target_name, source_id))
          end
          model.insert_all!([ writable_attributes(model, attrs) ])
          inserted.add(record_key(data))
        end
      end

      @records.each do |row|
        data = row["data"]
        model = Family::Backup.models.fetch(data["model"])
        attrs = target_attributes(data)
        # Shared market/merchant records are never overwritten by a family import.
        next if shared_record?(data) && @reused.include?(record_key(data))
        model.find(attrs["id"]).update_columns(writable_attributes(model, attrs).except("id"))
      end
    end

    def writable_attributes(model, attributes)
      attributes.except(*model.columns.select(&:virtual?).map(&:name))
    end

    def shared_record?(data)
      data["model"].in?(%w[Security Security::Price ExchangeRate ExchangeRatePair]) || (data["model"] == "Merchant" && data.dig("attributes", "type") == "ProviderMerchant")
    end

    def restore_attachments!
      @attachments.each do |row|
        data = row["data"]
        model = Family::Backup.models.fetch(data["model"])
        owner = model.find(@id_map.fetch(source_key(data["model"], data["record_id"])))
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new(Base64.strict_decode64(data["content"])), filename: data["filename"],
          content_type: data["content_type"], metadata: data["metadata"], identify: false
        )
        @uploaded_blobs << blob
        blob.open { |_file| } # Verify that storage returns the bytes we uploaded.
        blob.update_columns(created_at: data["blob_created_at"]) if data["blob_created_at"]
        association = owner.public_send(data["name"])
        if owner.class.attachment_reflections[data["name"]].macro == :has_one_attached
          association.attachment&.destroy!
        end
        ActiveStorage::Attachment.create!(record: owner, name: data["name"], blob: blob, created_at: data["created_at"])
      end
      # Active Storage touches owners; preserve the snapshot's original times.
      @records.each do |row|
        data = row["data"]
        next if shared_record?(data) && @reused.include?(record_key(data))
        model = Family::Backup.models.fetch(data["model"])
        times = target_attributes(data).slice("created_at", "updated_at")
        model.find(@id_map.fetch(record_key(data))).update_columns(times) if times.any?
      end
    end

    def verify_records!
      @records.each do |row|
        data = row["data"]
        model = Family::Backup.models.fetch(data["model"])
        expected = target_attributes(data)
        actual = model.find(expected["id"])
        expected.each do |field, value|
          next if field == "password_digest"
          cast = model.type_for_attribute(field).cast(value)
          fail_backup("Restored #{model.name}.#{field} differs from backup") unless actual[field] == cast
        end
      end
    end

    def verify_attachments!
      verified = Set.new
      @attachments.each do |row|
        data = row["data"]
        candidates = ActiveStorage::Attachment.includes(:blob).where(
          record_type: Family::Backup.models.fetch(data["model"]).base_class.name,
          record_id: @id_map.fetch(source_key(data["model"], data["record_id"])), name: data["name"]
        )
        attachment = candidates.find do |candidate|
          blob = candidate.blob
          !verified.include?(candidate.id) && blob.filename.to_s == data["filename"] &&
            blob.checksum == data["checksum"] && blob.byte_size == data["byte_size"] && blob.content_type == data["content_type"]
        end
        fail_backup("Restored attachment is missing or differs from backup") unless attachment
        attachment.blob.open { |_file| }
        verified.add(attachment.id)
      end
    end

    def result
      accounts = @family.accounts.where(id: @records.filter_map { |row| @id_map[record_key(row["data"])] if row.dig("data", "model") == "Account" }).to_a
      entries = @family.entries.where(id: @records.filter_map { |row| @id_map[record_key(row["data"])] if row.dig("data", "model") == "Entry" }).to_a
      summary = @records.each_with_object({}) do |row, totals|
        data = row["data"]
        next if data["model"] == "Family"
        key = Family::Backup.models.fetch(data["model"]).table_name
        totals[key] ||= { "created" => 0, "updated" => 0, "skipped" => 0, "failed" => 0 }
        totals[key][@reused.include?(record_key(data)) ? "updated" : "created"] += 1
      end
      {
        accounts: accounts, entries: entries,
        summary: summary.merge("backup_restore" => { "sha256" => @manifest["sha256"], "id_map" => @id_map }),
        verification: { "status" => "matched", "checked_at" => Time.current.iso8601, "expected_record_counts" => counts, "verified_records" => @records.size, "verified_attachments" => @attachments.size, "warnings" => warnings }
      }
    end
end
