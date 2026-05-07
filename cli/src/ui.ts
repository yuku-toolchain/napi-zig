import { stdout } from "node:process";
import readline from "node:readline";

const isTTY = !!stdout.isTTY;
const colorOn = isTTY && !("NO_COLOR" in process.env);

const E = (code: number): string => (colorOn ? `\x1b[${code}m` : "");
const RESET = colorOn ? "\x1b[0m" : "";

type ColorFn = (s: string | number) => string;
const wrap =
  (open: string): ColorFn =>
  (s: string | number): string =>
    colorOn ? `${open}${s}${RESET}` : String(s);

export interface Colors {
  reset: string;
  bold: ColorFn;
  dim: ColorFn;
  italic: ColorFn;
  underline: ColorFn;
  inverse: ColorFn;
  red: ColorFn;
  green: ColorFn;
  yellow: ColorFn;
  blue: ColorFn;
  magenta: ColorFn;
  cyan: ColorFn;
  gray: ColorFn;
  brightRed: ColorFn;
  brightGreen: ColorFn;
  brightYellow: ColorFn;
  brightCyan: ColorFn;
}

export const c: Colors = {
  reset: RESET,
  bold: wrap(E(1)),
  dim: wrap(E(2)),
  italic: wrap(E(3)),
  underline: wrap(E(4)),
  inverse: wrap(E(7)),
  red: wrap(E(31)),
  green: wrap(E(32)),
  yellow: wrap(E(33)),
  blue: wrap(E(34)),
  magenta: wrap(E(35)),
  cyan: wrap(E(36)),
  gray: wrap(E(90)),
  brightRed: wrap(E(91)),
  brightGreen: wrap(E(92)),
  brightYellow: wrap(E(93)),
  brightCyan: wrap(E(96)),
};

export interface Symbols {
  ok: string;
  fail: string;
  warn: string;
  info: string;
  pending: string;
  active: string;
  arrow: string;
  bullet: string;
  dot: string;
  pipe: string;
  tee: string;
  corner: string;
}

export const sym: Symbols = {
  ok: "✓",
  fail: "✗",
  warn: "⚠",
  info: "ℹ",
  pending: "○",
  active: "●",
  arrow: "›",
  bullet: "•",
  dot: "·",
  pipe: "│",
  tee: "├",
  corner: "└",
};

const SPINNER = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];

const PAD = "  ";

export function blank(): void {
  console.log();
}

export function banner(title: string, subtitle?: string): void {
  const dot = c.gray(sym.dot);
  const head = c.cyan(c.bold(title));
  const sub = subtitle ? `  ${dot}  ${c.dim(subtitle)}` : "";
  console.log();
  console.log(`${PAD}${head}${sub}`);
  console.log();
}

export function done(text: string, dur?: number): void {
  console.log(
    `${PAD}${c.green(sym.ok)}  ${text}${dur !== undefined ? "  " + c.gray(formatDuration(dur)) : ""}`,
  );
}

export function fail(text: string, dur?: number): void {
  console.log(
    `${PAD}${c.red(sym.fail)}  ${text}${dur !== undefined ? "  " + c.gray(formatDuration(dur)) : ""}`,
  );
}

export function warn(text: string): void {
  console.log(`${PAD}${c.yellow(sym.warn)}  ${text}`);
}

export function info(text: string): void {
  console.log(`${PAD}${c.blue(sym.info)}  ${text}`);
}

export function note(text: string): void {
  console.log(`${PAD}${c.gray(sym.dot)}  ${c.dim(text)}`);
}

export function bullet(text: string): void {
  console.log(`${PAD}${c.gray(sym.bullet)}  ${text}`);
}

export function plain(text: string): void {
  console.log(`${PAD}${text}`);
}

export function rule(label?: string): void {
  if (label) console.log(`${PAD}${c.gray("──  " + label + "  ──")}`);
  else console.log(`${PAD}${c.gray("───────────────")}`);
}

export function formatDuration(ms: number): string {
  if (ms < 1000) return `${ms}ms`;
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`;
  const m = Math.floor(ms / 60_000);
  const s = Math.round((ms % 60_000) / 1000);
  return `${m}m${s.toString().padStart(2, "0")}s`;
}

export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(2)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(2)} GB`;
}

const ANSI_RE = new RegExp(String.fromCharCode(27) + "\\[[0-9;]*m", "g");
export function stripAnsi(s: string): string {
  return s.replace(ANSI_RE, "");
}

class LiveBlock {
  private linesWritten = 0;
  private hidCursor = false;

  write(content: string): void {
    if (!isTTY) return;
    const normalized = content.endsWith("\n") ? content : content + "\n";
    if (!this.hidCursor) {
      stdout.write("\x1b[?25l");
      this.hidCursor = true;
    }
    if (this.linesWritten > 0) {
      readline.moveCursor(stdout, 0, -this.linesWritten);
      readline.cursorTo(stdout, 0);
      readline.clearScreenDown(stdout);
    }
    stdout.write(normalized);
    this.linesWritten = normalized.split("\n").length - 1;
  }

  finish(content?: string): void {
    if (content !== undefined) {
      if (isTTY) {
        this.write(content);
      } else {
        const normalized = content.endsWith("\n") ? content : content + "\n";
        stdout.write(normalized);
      }
    }
    if (this.hidCursor) {
      stdout.write("\x1b[?25h");
      this.hidCursor = false;
    }
    this.linesWritten = 0;
  }
}

export class Spinner {
  private label: string;
  private hint?: string;
  private started = 0;
  private timer?: NodeJS.Timeout;
  private frame = 0;
  private block = new LiveBlock();
  private active = false;

  constructor(label: string) {
    this.label = label;
  }

  start(label?: string): this {
    if (label !== undefined) this.label = label;
    this.started = Date.now();
    this.active = true;
    if (isTTY) {
      this.timer = setInterval(() => this.render(), 80);
    }
    this.render();
    return this;
  }

  setLabel(label: string): void {
    this.label = label;
    if (this.active) this.render();
  }

  setHint(hint: string | undefined): void {
    this.hint = hint;
    if (this.active) this.render();
  }

  succeed(label?: string, hint?: string): void {
    this.stopTimer();
    const dur = Date.now() - this.started;
    const text = label ?? this.label;
    const h = hint !== undefined ? "  " + c.dim(hint) : "";
    this.block.finish(`${PAD}${c.green(sym.ok)}  ${text}${h}  ${c.gray(formatDuration(dur))}\n`);
  }

  fail(label?: string, hint?: string): void {
    this.stopTimer();
    const dur = Date.now() - this.started;
    const text = label ?? this.label;
    const h = hint !== undefined ? "  " + c.dim(hint) : "";
    this.block.finish(`${PAD}${c.red(sym.fail)}  ${text}${h}  ${c.gray(formatDuration(dur))}\n`);
  }

  warn(label?: string): void {
    this.stopTimer();
    const text = label ?? this.label;
    this.block.finish(`${PAD}${c.yellow(sym.warn)}  ${text}\n`);
  }

  stop(): void {
    this.stopTimer();
    this.block.finish();
  }

  private stopTimer(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    this.active = false;
  }

  private render(): void {
    const f = isTTY ? c.cyan(SPINNER[this.frame % SPINNER.length]!) : c.cyan(sym.active);
    this.frame++;
    const dur = Date.now() - this.started;
    const h = this.hint !== undefined ? "  " + c.dim(this.hint) : "";
    this.block.write(`${PAD}${f}  ${this.label}${h}  ${c.gray(formatDuration(dur))}`);
  }
}

export type TaskState = "pending" | "active" | "ok" | "fail" | "skip";
export interface Task {
  id: string;
  label: string;
  state: TaskState;
  note?: string;
  startedAt?: number;
}

export class TaskList {
  private tasks: Task[];
  private header: string;
  private hint?: string;
  private startedAt = 0;
  private timer?: NodeJS.Timeout;
  private frame = 0;
  private block = new LiveBlock();
  private columns: number;
  private active = false;

  constructor(
    header: string,
    tasks: { id: string; label: string; state?: TaskState }[],
    options?: { columns?: number; hint?: string },
  ) {
    this.header = header;
    this.tasks = tasks.map((t) => ({
      id: t.id,
      label: t.label,
      state: t.state ?? "pending",
    }));
    this.columns = options?.columns ?? 1;
    this.hint = options?.hint;
  }

  start(): this {
    this.startedAt = Date.now();
    this.active = true;
    for (const t of this.tasks) {
      if (t.state === "active") t.startedAt = Date.now();
    }
    if (isTTY) this.timer = setInterval(() => this.render(), 80);
    this.render();
    return this;
  }

  begin(id: string): void {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.state = "active";
    t.startedAt = Date.now();
    if (this.active) this.render();
  }

  beginAll(): void {
    for (const t of this.tasks) {
      if (t.state === "pending") {
        t.state = "active";
        t.startedAt = Date.now();
      }
    }
    if (this.active) this.render();
  }

  setState(id: string, state: TaskState, note?: string): void {
    const t = this.tasks.find((x) => x.id === id);
    if (!t) return;
    t.state = state;
    if (note !== undefined) t.note = note;
    if (this.active) this.render();
  }

  setHint(hint: string | undefined): void {
    this.hint = hint;
    if (this.active) this.render();
  }

  setHeader(header: string): void {
    this.header = header;
    if (this.active) this.render();
  }

  resolveRemaining(state: TaskState): void {
    for (const t of this.tasks) {
      if (t.state === "active" || t.state === "pending") t.state = state;
    }
    if (this.active) this.render();
  }

  finish(success: boolean, finalLabel?: string): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    this.active = false;
    const dur = Date.now() - this.startedAt;
    const final = this.renderTo(success ? "ok" : "fail", dur, finalLabel);
    this.block.finish(final);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = undefined;
    this.active = false;
    this.block.finish();
  }

  private spinnerFrame(): string {
    const f = isTTY ? SPINNER[this.frame % SPINNER.length]! : sym.active;
    this.frame++;
    return f;
  }

  private taskSymbol(t: Task, spinner: string): string {
    switch (t.state) {
      case "ok":
        return c.green(sym.ok);
      case "fail":
        return c.red(sym.fail);
      case "skip":
        return c.gray(sym.dot);
      case "active":
        return c.cyan(spinner);
      case "pending":
      default:
        return c.gray(sym.pending);
    }
  }

  private formatLabel(t: Task): string {
    let label = t.label;
    if (t.state === "ok") label = c.gray(label);
    else if (t.state === "active") label = c.bold(label);
    else if (t.state === "fail") label = c.red(label);
    else if (t.state === "pending") label = c.gray(label);
    else if (t.state === "skip") label = c.gray(label);

    let suffix = "";
    if (t.note) suffix += "  " + c.dim(t.note);
    return label + suffix;
  }

  private render(): void {
    this.block.write(this.renderTo("active", Date.now() - this.startedAt));
  }

  private renderTo(
    headerState: "active" | "ok" | "fail",
    dur: number,
    finalLabel?: string,
  ): string {
    const spinner = this.spinnerFrame();
    const lines: string[] = [];

    let headSym: string;
    if (headerState === "ok") headSym = c.green(sym.ok);
    else if (headerState === "fail") headSym = c.red(sym.fail);
    else headSym = c.cyan(spinner);

    const head = finalLabel ?? this.header;
    const hintBit = this.hint ? "  " + c.dim(this.hint) : "";
    lines.push(`${PAD}${headSym}  ${head}${hintBit}  ${c.gray(formatDuration(dur))}`);

    if (this.columns <= 1) {
      for (const t of this.tasks) {
        lines.push(`${PAD}   ${this.taskSymbol(t, spinner)}  ${this.formatLabel(t)}`);
      }
    } else {
      const cols = this.columns;
      const cellWidth = this.tasks.reduce(
        (w, t) => Math.max(w, stripAnsi(this.formatLabel(t)).length),
        0,
      );
      for (let i = 0; i < this.tasks.length; i += cols) {
        const row = this.tasks.slice(i, i + cols);
        const parts = row.map((t) => {
          const label = this.formatLabel(t);
          const pad = " ".repeat(Math.max(0, cellWidth - stripAnsi(label).length));
          return `${this.taskSymbol(t, spinner)}  ${label}${pad}`;
        });
        lines.push(`${PAD}   ${parts.join("   ")}`);
      }
    }

    return lines.join("\n");
  }
}

export function printTargetList(
  header: string,
  targets: string[],
  options?: { columns?: number; symbol?: string; symbolColor?: (s: string) => string },
): void {
  const cols = options?.columns ?? 3;
  const symC = options?.symbolColor ?? c.gray;
  const s = options?.symbol ?? sym.dot;
  console.log(`${PAD}${c.dim(header)}`);
  const cellWidth = targets.reduce((w, t) => Math.max(w, t.length), 0);
  for (let i = 0; i < targets.length; i += cols) {
    const row = targets
      .slice(i, i + cols)
      .map((t) => `${symC(s)}  ${t.padEnd(cellWidth)}`)
      .join("   ");
    console.log(`${PAD}   ${row}`);
  }
}

export function isInteractive(): boolean {
  return isTTY;
}
