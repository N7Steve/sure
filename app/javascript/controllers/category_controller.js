import { Controller } from "@hotwired/stimulus";
import Pickr from "@simonwep/pickr";

export default class extends Controller {
  static targets = [
    "pickerBtn",
    "colorInput",
    "colorsSection",
    "paletteSection",
    "pickerSection",
    "colorPreview",
    "avatar",
    "details",
    "icon",
    "validationMessage",
    "selection",
    "colorPickerRadioBtn",
    "popup",
    "iconSearch",
    "iconGrid",
    "iconNoResults",
  ];

  static values = {
    presetColors: Array,
  };

  static ICON_KEYWORD_MAP = {
    "activity": "health fitness exercise heart",
    "alarm-clock": "time wake morning schedule",
    "ambulance": "emergency medical hospital health",
    "anchor": "boat sea marine nautical",
    "apple": "fruit food healthy snack",
    "archive": "storage box organize files",
    "award": "prize medal achievement trophy",
    "axe": "tool wood chop",
    "baby": "child infant kid family",
    "backpack": "bag school travel hiking",
    "badge-dollar-sign": "money finance price cost",
    "banana": "fruit food snack tropical",
    "banknote": "money cash bill payment currency",
    "barcode": "scan product shop retail",
    "bar-chart-3": "chart statistics data analytics graph",
    "bath": "bathroom shower wash hygiene",
    "battery": "power energy charge electric",
    "bed-double": "sleep bedroom hotel rest",
    "bed-single": "sleep bedroom rest",
    "beer": "drink alcohol bar pub brewery",
    "bell": "notification alert alarm reminder",
    "bike": "bicycle cycling transport exercise sport",
    "binoculars": "view look observe watch outdoor",
    "bitcoin": "crypto cryptocurrency digital currency",
    "bluetooth": "wireless connect device technology",
    "bone": "pet dog animal veterinary",
    "book": "read education study literature library",
    "book-open": "read education study learning",
    "box": "package shipping delivery storage",
    "briefcase": "work business office job career",
    "brush": "paint art creative clean",
    "building": "office company business city corporate",
    "bus": "transport transit commute public",
    "cable-car": "transport mountain ski gondola",
    "cake": "birthday celebration dessert party sweet",
    "calculator": "math finance accounting numbers",
    "calendar-heart": "date event love anniversary",
    "calendar-range": "date schedule period planning",
    "camera": "photo picture image photography",
    "candy": "sweet dessert sugar treat snack",
    "car": "vehicle auto drive transport",
    "carrot": "vegetable food healthy garden",
    "cat": "pet animal feline",
    "chart-line": "graph data statistics trend analytics",
    "cherry": "fruit food sweet berry",
    "church": "religion worship faith spiritual",
    "cigarette": "smoke tobacco habit",
    "circle-dollar-sign": "money income salary payment dollar",
    "circle-parking": "park car vehicle lot",
    "clipboard": "notes list tasks organize",
    "clock": "time schedule hour watch",
    "cloud": "weather sky storage hosting",
    "clover": "luck nature plant irish",
    "coffee": "drink cafe beverage morning hot",
    "coins": "money currency cash change",
    "compass": "direction navigation travel explore",
    "construction": "build work site renovation",
    "cookie": "bake dessert sweet snack treat",
    "cooking-pot": "kitchen cook food meal recipe",
    "credit-card": "payment bank card loan debt",
    "crown": "royal premium luxury vip",
    "cup-soda": "drink beverage soda soft",
    "dices": "game play casino luck gamble",
    "dog": "pet animal puppy canine",
    "door-closed": "room house entrance",
    "door-open": "room house entrance exit",
    "drama": "theater entertainment show performance art",
    "drill": "tool construction repair",
    "droplet": "water liquid rain",
    "drum": "music instrument band rhythm",
    "dumbbell": "gym fitness workout exercise sport weight",
    "ear": "hearing listen sound body",
    "egg": "food breakfast cooking",
    "eye": "vision see look watch",
    "factory": "manufacturing industry production work",
    "fan": "cool air ventilation home appliance",
    "fence": "garden yard boundary home outdoor",
    "ferris-wheel": "amusement park fun fair",
    "film": "movie cinema video entertainment",
    "fingerprint": "security identity biometric",
    "fish": "seafood food ocean animal sushi",
    "flag": "country nation marker milestone",
    "flame": "fire hot heat energy",
    "flashlight": "light torch dark outdoor",
    "flower": "plant garden nature bloom",
    "flower-2": "plant garden nature bloom rose",
    "fuel": "gas petrol station car energy",
    "gamepad-2": "gaming play console video controller",
    "gem": "jewel diamond luxury precious valuable",
    "ghost": "halloween spooky fun",
    "gift": "present birthday surprise celebration",
    "glasses": "eyewear vision reading optical",
    "globe": "world earth international travel global",
    "graduation-cap": "education school university degree study",
    "grape": "fruit wine vineyard food",
    "guitar": "music instrument band rock",
    "hammer": "tool repair build construction fix",
    "hand-coins": "payment tip donation give money",
    "hand-heart": "care love charity donate help",
    "hand-helping": "help charity donation give support",
    "handshake": "deal agreement partner business meeting",
    "headphones": "audio music listen podcast",
    "heart": "love health favorite like",
    "heart-handshake": "agreement love partnership trust",
    "heart-pulse": "health medical heartbeat vital",
    "home": "house residence living mortgage rent",
    "hotel": "accommodation stay travel lodging room",
    "house": "home residence living property",
    "ice-cream-cone": "dessert sweet treat frozen summer",
    "key": "security lock access password",
    "lamp": "light home interior decoration",
    "landmark": "government tax bank official building",
    "laptop": "computer work technology device",
    "laugh": "happy fun joy emoji",
    "leaf": "nature plant green eco organic",
    "library": "books reading education study",
    "lightbulb": "idea electricity utility power",
    "lock": "security protect private safe",
    "luggage": "travel trip bag suitcase journey",
    "mail": "email message letter communication",
    "map": "navigation direction location travel route",
    "map-pin": "location place address gps",
    "martini": "cocktail drink alcohol bar nightlife",
    "megaphone": "announcement marketing advertising promotion",
    "mic": "microphone record audio voice",
    "microscope": "science research lab study",
    "milk": "dairy drink beverage breakfast",
    "monitor": "screen display computer desktop",
    "moon": "night dark sleep sky",
    "mountain": "hiking outdoor nature adventure climb",
    "mountain-snow": "ski winter outdoor cold",
    "music": "song audio listen melody",
    "newspaper": "news press media article read",
    "nut": "food snack protein almond walnut",
    "package": "box delivery shipping order",
    "paintbrush": "art paint creative design",
    "palette": "art color paint creative design",
    "party-popper": "celebration event fun birthday confetti",
    "paw-print": "pet animal dog cat",
    "pen": "write sign draw",
    "pencil": "write draw edit note",
    "percent": "discount sale offer deal savings",
    "phone": "call telephone contact mobile",
    "pickaxe": "mine dig tool work",
    "pie-chart": "chart data statistics analytics",
    "piggy-bank": "save savings money bank invest",
    "pill": "medicine pharmacy drug health prescription",
    "pizza": "food delivery fast meal italian",
    "plane": "flight airline travel airport trip",
    "plug": "electric power connect outlet",
    "podcast": "audio listen show episode",
    "popcorn": "movie snack cinema entertainment",
    "power": "energy electric switch",
    "printer": "office print document paper",
    "puzzle": "game hobby brain challenge",
    "rabbit": "animal pet easter bunny",
    "radio": "music broadcast audio listen",
    "receipt": "bill payment purchase transaction invoice",
    "receipt-text": "bill payment purchase receipt invoice",
    "refrigerator": "kitchen fridge food appliance storage cold",
    "ribbon": "award gift decoration",
    "rocket": "startup launch space fast",
    "ruler": "measure tool size length",
    "sailboat": "boat water sea sailing ocean",
    "sandwich": "food lunch meal bread deli",
    "scale": "weight measure balance justice",
    "school": "education learning class student",
    "scissors": "cut hair salon barber",
    "settings": "configure options preferences gear",
    "shapes": "misc various general other",
    "shell": "beach sea ocean nature",
    "shield": "security protection insurance safety",
    "shield-plus": "security protection insurance add",
    "ship": "boat sea transport cruise ocean",
    "shirt": "clothing fashion apparel wear",
    "shopping-bag": "buy store retail purchase groceries",
    "shopping-basket": "buy store retail market",
    "shopping-cart": "buy store retail e-commerce purchase",
    "shovel": "dig garden tool yard",
    "smartphone": "mobile phone device cell app",
    "snowflake": "winter cold snow ski ice",
    "sofa": "furniture living room comfort home relax",
    "soup": "food meal warm bowl stew",
    "sparkles": "magic special shine new clean",
    "sprout": "plant grow garden nature seed",
    "star": "favorite rating review best",
    "stethoscope": "doctor medical health hospital",
    "store": "shop retail business market",
    "sun": "weather bright day summer warm",
    "syringe": "vaccine injection medical hospital",
    "tablet-smartphone": "device mobile technology screen",
    "tag": "label price category organize",
    "target": "goal aim focus objective",
    "tent": "camping outdoor adventure nature",
    "thermometer": "temperature weather health fever",
    "ticket": "event concert movie admission pass",
    "timer": "countdown time clock duration",
    "tractor": "farm agriculture vehicle rural",
    "train": "rail transport commute travel",
    "trees": "forest nature park green",
    "tree-palm": "tropical vacation beach paradise",
    "trending-down": "decrease loss decline negative",
    "trending-up": "increase profit growth positive invest",
    "trophy": "winner award champion prize",
    "truck": "delivery freight transport shipping",
    "tv": "television screen watch entertainment",
    "umbrella": "rain weather protection cover",
    "undo-2": "return refund reverse back",
    "unplug": "disconnect power off",
    "users": "people group team family friends",
    "utensils": "food dining restaurant eat meal",
    "video": "film record camera content",
    "wallet": "money payment cash finance personal",
    "wallet-cards": "payment credit card bank cards",
    "washing-machine": "laundry clean clothes appliance",
    "waves": "water ocean sea surf beach",
    "wheat": "grain bread food farm agriculture",
    "wifi": "internet connection wireless network subscription",
    "wine": "drink alcohol vineyard bar restaurant",
    "wrench": "repair fix tool maintenance",
    "zap": "electric energy power lightning fast",
  };

  initialize() {
    this.pickerBtnTarget.addEventListener("click", () => {
      this.showPaletteSection();
    });

    this.colorInputTarget.addEventListener("input", (e) => {
      this.picker.setColor(e.target.value);
    });

    this.detailsTarget.addEventListener("toggle", (e) => {
      if (!this.colorInputTarget.checkValidity()) {
        e.preventDefault();
        this.colorInputTarget.reportValidity();
        e.target.open = true;
      }
      this.updatePopupPosition()
    });

    this.selectedIcon = null;

    if (!this.presetColorsValue.includes(this.colorInputTarget.value)) {
      this.colorPickerRadioBtnTarget.checked = true;
    }

    document.addEventListener("mousedown", this.handleOutsideClick);
  }

  initPicker() {
    const pickerContainer = document.createElement("div");
    pickerContainer.classList.add("pickerContainer");
    this.pickerSectionTarget.append(pickerContainer);

    this.picker = Pickr.create({
      el: this.pickerBtnTarget,
      theme: "monolith",
      container: ".pickerContainer",
      useAsButton: true,
      showAlways: true,
      default: this.colorInputTarget.value,
      components: {
        hue: true,
      },
    });

    this.picker.on("change", (color) => {
      const hexColor = color.toHEXA().toString();
      const rgbacolor = color.toRGBA();

      this.updateAvatarColors(hexColor);
      this.updateSelectedIconColor(hexColor);

      const backgroundColor = this.backgroundColor(rgbacolor, 10);
      const contrastRatio = this.contrast(rgbacolor, backgroundColor);

      this.colorInputTarget.value = hexColor;
      this.colorInputTarget.dataset.colorPickerColorValue = hexColor;
      this.colorPreviewTarget.style.backgroundColor = hexColor;

      this.handleContrastValidation(contrastRatio);
    });
  }

  updateAvatarColors(color) {
    this.avatarTarget.style.backgroundColor = `${this.#backgroundColor(color)}`;
    this.avatarTarget.style.color = color;
  }

  handleIconColorChange(e) {
    const selectedIcon = e.target;
    this.selectedIcon = selectedIcon;

    const currentColor = this.colorInputTarget.value;

    this.iconTargets.forEach((icon) => {
      const iconWrapper = icon.nextElementSibling;
      iconWrapper.style.removeProperty("background-color");
      iconWrapper.style.removeProperty("color");
    });

    this.updateSelectedIconColor(currentColor);
  }

  handleIconChange(e) {
    const iconSVG = e.currentTarget
      .closest("label")
      .querySelector("svg")
      .cloneNode(true);
    this.avatarTarget.innerHTML = "";
    iconSVG.style.padding = "0px";
    iconSVG.classList.add("w-8", "h-8");
    this.avatarTarget.appendChild(iconSVG);
  }

  filterIcons(e) {
    const query = e.target.value.toLowerCase().trim();
    const labels = this.iconGridTarget.querySelectorAll("label[data-icon-name]");
    let visibleCount = 0;

    labels.forEach((label) => {
      const iconName = label.dataset.iconName;
      const nameMatch = iconName.replace(/-/g, " ").includes(query);
      const keywords = this.constructor.ICON_KEYWORD_MAP[iconName] || "";
      const keywordMatch = keywords.includes(query);

      if (query === "" || nameMatch || keywordMatch) {
        label.classList.remove("hidden");
        visibleCount++;
      } else {
        label.classList.add("hidden");
      }
    });

    if (this.hasIconNoResultsTarget) {
      this.iconNoResultsTarget.classList.toggle("hidden", visibleCount > 0);
    }
  }

  updateSelectedIconColor(color) {
    if (this.selectedIcon) {
      const iconWrapper = this.selectedIcon.nextElementSibling;
      iconWrapper.style.backgroundColor = `${this.#backgroundColor(color)}`;
      iconWrapper.style.color = color;
    }
  }

  handleColorChange(e) {
    const color = e.currentTarget.value;
    this.colorInputTarget.value = color;
    this.colorPreviewTarget.style.backgroundColor = color;
    this.updateAvatarColors(color);
    this.updateSelectedIconColor(color);
  }

  handleContrastValidation(contrastRatio) {
    if (contrastRatio < 4.5) {
      this.colorInputTarget.setCustomValidity(
        "Poor contrast, choose darker color or auto-adjust.",
      );

      this.validationMessageTarget.classList.remove("hidden");
    } else {
      this.colorInputTarget.setCustomValidity("");
      this.validationMessageTarget.classList.add("hidden");
    }
  }

  autoAdjust(e) {
    const currentRGBA = this.picker.getColor();
    const adjustedRGBA = this.darkenColor(currentRGBA).toString();
    this.picker.setColor(adjustedRGBA);
  }

  handleParentChange(e) {
    const parent = e.currentTarget.value;
    const display =
      typeof parent === "string" && parent !== "" ? "none" : "flex";
    this.selectionTarget.style.display = display;
  }

  backgroundColor([r, g, b, a], percentage) {
    const mixedR = Math.round(
      r * (percentage / 100) + 255 * (1 - percentage / 100),
    );
    const mixedG = Math.round(
      g * (percentage / 100) + 255 * (1 - percentage / 100),
    );
    const mixedB = Math.round(
      b * (percentage / 100) + 255 * (1 - percentage / 100),
    );
    return [mixedR, mixedG, mixedB];
  }

  luminance([r, g, b]) {
    const toLinear = (c) => {
      const scaled = c / 255;
      return scaled <= 0.04045
        ? scaled / 12.92
        : ((scaled + 0.055) / 1.055) ** 2.4;
    };
    return 0.2126 * toLinear(r) + 0.7152 * toLinear(g) + 0.0722 * toLinear(b);
  }

  contrast(foregroundColor, backgroundColor) {
    const fgLum = this.luminance(foregroundColor);
    const bgLum = this.luminance(backgroundColor);
    const [l1, l2] = [Math.max(fgLum, bgLum), Math.min(fgLum, bgLum)];
    return (l1 + 0.05) / (l2 + 0.05);
  }

  darkenColor(color) {
    let darkened = color.toRGBA();
    const backgroundColor = this.backgroundColor(darkened, 10);
    let contrastRatio = this.contrast(darkened, backgroundColor);

    while (
      contrastRatio < 4.5 &&
      (darkened[0] > 0 || darkened[1] > 0 || darkened[2] > 0)
    ) {
      darkened = [
        Math.max(0, darkened[0] - 10),
        Math.max(0, darkened[1] - 10),
        Math.max(0, darkened[2] - 10),
        darkened[3],
      ];
      contrastRatio = this.contrast(darkened, backgroundColor);
    }

    return `rgba(${darkened.join(", ")})`;
  }

  showPaletteSection() {
    this.initPicker();
    this.colorsSectionTarget.classList.add("hidden");
    this.paletteSectionTarget.classList.remove("hidden");
    this.pickerSectionTarget.classList.remove("hidden");
    this.updatePopupPosition();
    this.picker.show();
  }

  showColorsSection() {
    this.colorsSectionTarget.classList.remove("hidden");
    this.paletteSectionTarget.classList.add("hidden");
    this.pickerSectionTarget.classList.add("hidden");
    this.updatePopupPosition()
    if (this.picker) {
      this.picker.destroyAndRemove();
    }
  }

  toggleSections() {
    if (this.colorsSectionTarget.classList.contains("hidden")) {
      this.showColorsSection();
    } else {
      this.showPaletteSection();
    }
  }

  handleOutsideClick = (event) => {
    if (this.detailsTarget.open && !this.detailsTarget.contains(event.target)) {
      this.detailsTarget.open = false;
    }
  };

  updatePopupPosition() {
    const popup = this.popupTarget;
    popup.style.top = "";
    popup.style.bottom = "";

    const rect = popup.getBoundingClientRect();
    const overflow = rect.bottom > window.innerHeight;

    if (overflow) {
      popup.style.bottom = "0px";
    } else {
      popup.style.bottom = "";
    }
  }

  #backgroundColor(color) {
    return `color-mix(in oklab, ${color} 10%, transparent)`;
  }
}
