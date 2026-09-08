import { Controller } from "@hotwired/stimulus";
import * as d3 from "d3";
import { CHART_TOOLTIP_CLASSES } from "utils/chart_tooltip";

const COLORS = {
  pessimistic: "var(--color-destructive)",
  normal: "var(--color-info)",
  optimistic: "var(--color-success)",
};

export default class extends Controller {
  static values = { data: Object };

  connect() {
    this.install();
    this.resizeObserver = new ResizeObserver(() => this.reinstall());
    this.resizeObserver.observe(this.element);
    document.addEventListener("turbo:load", this.reinstall);
  }

  disconnect() {
    this.resizeObserver?.disconnect();
    document.removeEventListener("turbo:load", this.reinstall);
    this.teardown();
  }

  reinstall = () => {
    this.teardown();
    this.install();
  };

  teardown() {
    d3.select(this.element).selectAll("*").remove();
  }

  install() {
    const width = this.element.clientWidth;
    const height = this.element.clientHeight;
    const rawPoints = this.dataValue?.points || [];
    if (width < 80 || height < 80 || rawPoints.length < 2) return;

    const points = rawPoints.map((point) => ({
      ...point,
      parsedDate: new Date(`${point.date}T00:00:00`),
    }));
    const margin = { top: 12, right: 60, bottom: 28, left: 8 };
    const innerWidth = width - margin.left - margin.right;
    const innerHeight = height - margin.top - margin.bottom;
    const values = points.flatMap((point) =>
      Object.keys(COLORS).map((key) => point[key].amount),
    );

    const x = d3
      .scaleTime()
      .domain(d3.extent(points, (point) => point.parsedDate))
      .range([0, innerWidth]);
    const y = d3
      .scaleLinear()
      .domain(d3.extent(values))
      .nice()
      .range([innerHeight, 0]);
    if (y.domain()[0] === y.domain()[1]) {
      y.domain([y.domain()[0] - 1, y.domain()[1] + 1]);
    }

    const svg = d3
      .select(this.element)
      .append("svg")
      .attr("width", width)
      .attr("height", height)
      .attr("viewBox", [0, 0, width, height]);
    const group = svg
      .append("g")
      .attr("transform", `translate(${margin.left},${margin.top})`);

    this.drawAxes(group, x, y, points, innerWidth, innerHeight);
    this.drawBand(group, x, y, points);
    this.drawLines(group, x, y, points);
    this.installTooltip(group, x, y, points, innerWidth, innerHeight);
  }

  drawAxes(group, x, y, points, innerWidth, innerHeight) {
    const yTicks = y.ticks(4);
    group
      .append("g")
      .selectAll("line")
      .data(yTicks)
      .join("line")
      .attr("x2", innerWidth)
      .attr("y1", (value) => y(value))
      .attr("y2", (value) => y(value))
      .attr("class", "text-subdued")
      .attr("stroke", "currentColor")
      .attr("stroke-dasharray", "4,4")
      .attr("stroke-opacity", 0.5);

    group
      .append("g")
      .attr("transform", `translate(${innerWidth},0)`)
      .call(
        d3
          .axisRight(y)
          .tickValues(yTicks)
          .tickSize(0)
          .tickPadding(8)
          .tickFormat((value) => d3.format("~s")(value)),
      )
      .call((axis) => axis.select(".domain").remove())
      .selectAll("text")
      .attr("class", "text-secondary fill-current")
      .style("font-size", "12px");

    const indexes = [0, Math.floor((points.length - 1) / 2), points.length - 1];
    const ticks = [...new Set(indexes)].map((index) => points[index]);
    const labels = new Map(
      ticks.map((point) => [+point.parsedDate, point.label]),
    );
    group
      .append("g")
      .attr("transform", `translate(0,${innerHeight})`)
      .call(
        d3
          .axisBottom(x)
          .tickValues(ticks.map((point) => point.parsedDate))
          .tickSize(0)
          .tickPadding(9)
          .tickFormat((date) => labels.get(+date)),
      )
      .call((axis) => axis.select(".domain").remove())
      .selectAll("text")
      .attr("class", "text-secondary fill-current")
      .style("font-size", "12px")
      .attr("text-anchor", (_, index) =>
        index === 0 ? "start" : index === ticks.length - 1 ? "end" : "middle",
      );
  }

  drawBand(group, x, y, points) {
    const area = d3
      .area()
      .x((point) => x(point.parsedDate))
      .y0((point) => y(point.pessimistic.amount))
      .y1((point) => y(point.optimistic.amount))
      .curve(d3.curveLinear);
    group
      .append("path")
      .datum(points)
      .attr("d", area)
      .attr("fill", COLORS.normal)
      .attr("fill-opacity", 0.08);
  }

  drawLines(group, x, y, points) {
    for (const key of ["pessimistic", "optimistic", "normal"]) {
      const line = d3
        .line()
        .x((point) => x(point.parsedDate))
        .y((point) => y(point[key].amount))
        .curve(d3.curveLinear);
      group
        .append("path")
        .datum(points)
        .attr("fill", "none")
        .attr("stroke", COLORS[key])
        .attr("stroke-width", key === "normal" ? 2.5 : 1.5)
        .attr("stroke-linecap", "round")
        .attr("stroke-linejoin", "round")
        .attr("d", line);
    }
  }

  installTooltip(group, x, y, points, innerWidth, innerHeight) {
    const tooltip = d3
      .select(this.element)
      .append("div")
      .attr("class", `${CHART_TOOLTIP_CLASSES} opacity-0 top-0`);
    const bisect = d3.bisector((point) => point.parsedDate).center;

    group
      .append("rect")
      .attr("width", innerWidth)
      .attr("height", innerHeight)
      .attr("fill", "none")
      .attr("pointer-events", "all")
      .on("mousemove", (event) => {
        const [cursorX] = d3.pointer(event);
        const index = bisect(points, x.invert(cursorX));
        const point = points[Math.max(0, Math.min(index, points.length - 1))];
        group.selectAll(".forecast-guideline,.forecast-dot").remove();
        group
          .append("line")
          .attr("class", "forecast-guideline text-subdued")
          .attr("x1", x(point.parsedDate))
          .attr("x2", x(point.parsedDate))
          .attr("y2", innerHeight)
          .attr("stroke", "currentColor")
          .attr("stroke-dasharray", "4,4");

        for (const key of Object.keys(COLORS)) {
          group
            .append("circle")
            .attr("class", "forecast-dot")
            .attr("cx", x(point.parsedDate))
            .attr("cy", y(point[key].amount))
            .attr("r", key === "normal" ? 3.5 : 2.5)
            .attr("fill", COLORS[key]);
        }

        tooltip.selectAll("*").remove();
        tooltip
          .append("p")
          .attr("class", "text-xs text-secondary mb-1")
          .text(point.label);
        for (const key of ["normal", "optimistic", "pessimistic"]) {
          const row = tooltip
            .append("p")
            .attr("class", "flex justify-between gap-4");
          row.append("span").text(this.dataValue.scenario_labels[key]);
          row
            .append("span")
            .attr("class", "font-medium tabular-nums")
            .text(point[key].formatted);
        }
        const tooltipX = Math.min(
          event.pageX + 10,
          document.body.clientWidth - 230,
        );
        tooltip
          .style("left", `${Math.max(8, tooltipX)}px`)
          .style("top", `${event.pageY - 20}px`)
          .style("opacity", 1);
      })
      .on("mouseleave", () => {
        group.selectAll(".forecast-guideline,.forecast-dot").remove();
        tooltip.style("opacity", 0);
      });
  }
}
