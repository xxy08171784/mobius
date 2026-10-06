from __future__ import annotations

import os
import shutil
import subprocess
import tkinter as tk
from pathlib import Path
from tkinter import filedialog, messagebox, ttk

from PIL import Image, ImageTk

import core


IMAGE_TYPES = [
    ("PNG 图片", "*.png"),
    ("常见图片", "*.png;*.jpg;*.jpeg;*.webp"),
    ("所有文件", "*.*"),
]


class CardEditorApp(tk.Tk):
    def __init__(self) -> None:
        super().__init__()
        core.ensure_dirs()
        self.title("GAMEGAM Card Editor")
        self.geometry("1500x900")
        self.minsize(1180, 760)

        self.cards: list[core.CardData] = []
        self.card_by_id: dict[str, core.CardData] = {}
        self.visuals: dict[str, core.VisualConfig] = core.load_visual_db()
        self.current_card_id: str | None = None
        self.frame_assets: dict[str, Path] = {}
        self.icon_assets: dict[str, Path] = {}
        self._loading_form = False

        self.preview_photo: ImageTk.PhotoImage | None = None
        self.preview_scale = 1.0
        self.drag_start: tuple[int, int] | None = None
        self.preview_after_id: str | None = None

        self.atlas_source: Path | None = None
        self.atlas_source_image: Image.Image | None = None
        self.atlas_tiles: list[Image.Image] = []
        self.crop_boxes: list[list[float]] = []
        self.atlas_photo: ImageTk.PhotoImage | None = None
        self.atlas_render_key: tuple[int, int, int] | None = None
        self.atlas_tile_photo: ImageTk.PhotoImage | None = None
        self.atlas_draw_box = (0, 0, 1, 1)
        self.atlas_scale = 1.0
        self.atlas_origin = (0.0, 0.0)
        self.atlas_selected_index = 0
        self.atlas_drag_mode: str | None = None
        self.atlas_drag_start: tuple[float, float] | None = None
        self.atlas_drag_original: list[float] | None = None
        self.atlas_after_id: str | None = None
        self.grid_reset_after_id: str | None = None

        self._build_style()
        self._build_ui()
        self.reload_cards()
        self.refresh_asset_choices()
        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _build_style(self) -> None:
        style = ttk.Style(self)
        try:
            style.theme_use("vista")
        except tk.TclError:
            pass
        style.configure("Section.TLabelframe", padding=8)
        style.configure("Toolbar.TButton", padding=(10, 6))

    def _build_ui(self) -> None:
        top = ttk.Frame(self, padding=(12, 10))
        top.pack(fill="x")
        ttk.Label(
            top,
            text="GAMEGAM Card Editor",
            font=("Microsoft YaHei UI", 18, "bold"),
        ).pack(side="left")
        ttk.Label(
            top,
            text=f"项目：{core.PROJECT_ROOT}",
            foreground="#666666",
        ).pack(side="left", padx=(16, 0))
        ttk.Button(
            top,
            text="打开生成目录",
            style="Toolbar.TButton",
            command=lambda: self._open_folder(core.GENERATED_DIR),
        ).pack(side="right")

        self.notebook = ttk.Notebook(self)
        self.notebook.pack(fill="both", expand=True, padx=12, pady=(0, 12))
        self.editor_tab = ttk.Frame(self.notebook)
        self.atlas_tab = ttk.Frame(self.notebook)
        self.help_tab = ttk.Frame(self.notebook)
        self.notebook.add(self.editor_tab, text="卡牌编辑器")
        self.notebook.add(self.atlas_tab, text="图集切割器")
        self.notebook.add(self.help_tab, text="说明")
        self._build_editor_tab()
        self._build_atlas_tab()
        self._build_help_tab()

    def _build_editor_tab(self) -> None:
        paned = ttk.Panedwindow(self.editor_tab, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, padding=8, width=260)
        center = ttk.Frame(paned, padding=8)
        right = ttk.Frame(paned, padding=8, width=390)
        paned.add(left, weight=1)
        paned.add(center, weight=3)
        paned.add(right, weight=2)

        card_header = ttk.Frame(left)
        card_header.pack(fill="x")
        ttk.Label(card_header, text="现有卡牌（只读）", font=("Microsoft YaHei UI", 11, "bold")).pack(side="left")
        ttk.Button(card_header, text="重新读取", command=self.reload_cards).pack(side="right")
        self.card_list = tk.Listbox(left, exportselection=False, font=("Microsoft YaHei UI", 10))
        self.card_list.pack(fill="both", expand=True, pady=(8, 8))
        self.card_list.bind("<<ListboxSelect>>", self._on_card_selected)
        self.card_source_label = ttk.Label(left, text="", wraplength=240, foreground="#666666")
        self.card_source_label.pack(fill="x", pady=(0, 8))
        ttk.Button(left, text="保存全部视觉配置", command=self.save_visuals).pack(fill="x")
        ttk.Button(left, text="生成全部已配置卡牌 PNG", command=self.sync_all).pack(fill="x", pady=(6, 0))

        preview_header = ttk.Frame(center)
        preview_header.pack(fill="x")
        ttk.Label(preview_header, text="实时预览", font=("Microsoft YaHei UI", 11, "bold")).pack(side="left")
        drag_controls = ttk.Frame(preview_header)
        drag_controls.pack(side="right")
        ttk.Label(drag_controls, text="拖动调整：", foreground="#666666").pack(side="left")
        self.preview_drag_target_var = tk.StringVar(value="icon")
        ttk.Radiobutton(
            drag_controls,
            text="主图标",
            value="icon",
            variable=self.preview_drag_target_var,
        ).pack(side="left")
        ttk.Radiobutton(
            drag_controls,
            text="费用",
            value="cost",
            variable=self.preview_drag_target_var,
        ).pack(side="left", padx=(6, 0))
        self.preview_canvas = tk.Canvas(
            center,
            bg="#202226",
            highlightthickness=1,
            highlightbackground="#55585f",
            cursor="fleur",
        )
        self.preview_canvas.pack(fill="both", expand=True, pady=(8, 8))
        self.preview_canvas.bind("<Configure>", lambda _e: self.render_preview())
        self.preview_canvas.bind("<ButtonPress-1>", self._preview_drag_start)
        self.preview_canvas.bind("<B1-Motion>", self._preview_drag_move)
        self.preview_canvas.bind("<ButtonRelease-1>", self._preview_drag_end)
        self.editor_status = ttk.Label(center, text="请选择一张卡牌。", anchor="w")
        self.editor_status.pack(fill="x")

        side_tabs = ttk.Notebook(right)
        side_tabs.pack(fill="both", expand=True)
        self.art_page = ttk.Frame(side_tabs)
        side_tabs.add(self.art_page, text="卡牌美术")

        self.art_page.rowconfigure(0, weight=1)
        self.art_page.columnconfigure(0, weight=1)
        self.editor_options_canvas = tk.Canvas(
            self.art_page,
            highlightthickness=0,
            borderwidth=0,
            background=self.cget("background"),
        )
        editor_scrollbar = ttk.Scrollbar(
            self.art_page,
            orient="vertical",
            command=self.editor_options_canvas.yview,
        )
        self.editor_options_canvas.configure(yscrollcommand=editor_scrollbar.set)
        self.editor_options_canvas.grid(row=0, column=0, sticky="nsew")
        editor_scrollbar.grid(row=0, column=1, sticky="ns")

        art_content = ttk.Frame(self.editor_options_canvas, padding=6)
        self.editor_options_window = self.editor_options_canvas.create_window(
            (0, 0),
            window=art_content,
            anchor="nw",
        )
        art_content.bind("<Configure>", self._on_editor_options_content_configure)
        self.editor_options_canvas.bind("<Configure>", self._on_editor_options_canvas_configure)

        info = ttk.LabelFrame(art_content, text="卡牌信息（只读）", style="Section.TLabelframe")
        info.pack(fill="x")
        self.info_name = ttk.Label(info, text="卡名：-")
        self.info_name.pack(fill="x")
        self.info_cost = ttk.Label(info, text="费用：-")
        self.info_cost.pack(fill="x")
        self.info_tags = ttk.Label(info, text="标签：-")
        self.info_tags.pack(fill="x")
        self.info_desc = ttk.Label(info, text="描述：-", wraplength=340, justify="left")
        self.info_desc.pack(fill="x")

        assets = ttk.LabelFrame(art_content, text="美术素材", style="Section.TLabelframe")
        assets.pack(fill="x", pady=(8, 0))
        self.frame_var = tk.StringVar()
        self.icon_var = tk.StringVar()
        self.frame_combo = self._asset_row(
            assets, "卡框", self.frame_var, self._on_frame_combo, lambda: self._import_single_asset("frame")
        )
        self.icon_combo = self._asset_row(
            assets, "主图标", self.icon_var, self._on_icon_combo, lambda: self._import_single_asset("icon")
        )
        ttk.Button(assets, text="刷新素材库", command=self.refresh_asset_choices).pack(fill="x", pady=(6, 0))

        frame_transform = ttk.LabelFrame(art_content, text="卡框适配（默认铺满卡牌）", style="Section.TLabelframe")
        frame_transform.pack(fill="x", pady=(8, 0))
        self.frame_x_var = tk.DoubleVar(value=0)
        self.frame_y_var = tk.DoubleVar(value=0)
        self.frame_scale_var = tk.DoubleVar(value=1.0)
        self._scale_row(frame_transform, "X", self.frame_x_var, -180, 180)
        self._scale_row(frame_transform, "Y", self.frame_y_var, -220, 220)
        self._scale_row(frame_transform, "缩放", self.frame_scale_var, 0.5, 1.5)

        transform = ttk.LabelFrame(art_content, text="主图标位置", style="Section.TLabelframe")
        transform.pack(fill="x", pady=(8, 0))
        self.icon_x_var = tk.DoubleVar(value=0)
        self.icon_y_var = tk.DoubleVar(value=-65)
        self.icon_scale_var = tk.DoubleVar(value=0.72)
        self.icon_rotation_var = tk.DoubleVar(value=0)
        self._scale_row(transform, "X", self.icon_x_var, -180, 180)
        self._scale_row(transform, "Y", self.icon_y_var, -220, 180)
        self._scale_row(transform, "缩放", self.icon_scale_var, 0.15, 1.35)
        self._scale_row(transform, "旋转", self.icon_rotation_var, -180, 180)

        cost_position = ttk.LabelFrame(
            art_content,
            text="费用位置（也可在预览中直接拖动）",
            style="Section.TLabelframe",
        )
        cost_position.pack(fill="x", pady=(8, 0))
        self.cost_x_var = tk.DoubleVar(value=355)
        self.cost_y_var = tk.DoubleVar(value=55)
        self._scale_row(cost_position, "X", self.cost_x_var, 0, core.CARD_SIZE[0])
        self._scale_row(cost_position, "Y", self.cost_y_var, 0, core.CARD_SIZE[1])

        layout = ttk.LabelFrame(art_content, text="文字布局", style="Section.TLabelframe")
        layout.pack(fill="x", pady=(8, 0))
        self.title_y_var = tk.IntVar(value=350)
        self.desc_y_var = tk.IntVar(value=430)
        self.title_size_var = tk.IntVar(value=30)
        self.desc_size_var = tk.IntVar(value=22)
        self.cost_size_var = tk.IntVar(value=34)
        self.text_width_var = tk.IntVar(value=300)
        grid = ttk.Frame(layout)
        grid.pack(fill="x")
        fields = [
            ("标题 Y", self.title_y_var),
            ("描述 Y", self.desc_y_var),
            ("标题字号", self.title_size_var),
            ("描述字号", self.desc_size_var),
            ("费用字号", self.cost_size_var),
            ("文本宽度", self.text_width_var),
        ]
        for idx, (label, var) in enumerate(fields):
            row, col = divmod(idx, 2)
            ttk.Label(grid, text=label).grid(row=row, column=col * 2, sticky="w", padx=(0, 4), pady=3)
            spin = ttk.Spinbox(grid, textvariable=var, from_=-100, to=700, width=7, command=self._on_visual_changed)
            spin.grid(row=row, column=col * 2 + 1, sticky="ew", padx=(0, 8), pady=3)
            spin.bind("<KeyRelease>", lambda _e: self._on_visual_changed())
        grid.columnconfigure(1, weight=1)
        grid.columnconfigure(3, weight=1)

        actions = ttk.LabelFrame(art_content, text="输出", style="Section.TLabelframe")
        actions.pack(fill="x", pady=(8, 0))
        row = ttk.Frame(actions)
        row.pack(fill="x")
        ttk.Button(row, text="保存配置", command=self.save_visuals).pack(side="left", fill="x", expand=True)
        ttk.Button(row, text="导出当前 PNG…", command=self.export_current).pack(side="left", fill="x", expand=True, padx=(6, 0))
        ttk.Button(actions, text="生成全部已配置卡牌 PNG", command=self.sync_all).pack(fill="x", pady=(6, 0))
        ttk.Button(actions, text="恢复默认布局", command=self.reset_layout).pack(fill="x", pady=(6, 0))

        for variable in (
            self.frame_x_var, self.frame_y_var, self.frame_scale_var,
            self.icon_x_var, self.icon_y_var, self.icon_scale_var, self.icon_rotation_var,
            self.title_y_var, self.desc_y_var, self.cost_x_var, self.cost_y_var,
            self.title_size_var, self.desc_size_var, self.cost_size_var, self.text_width_var,
        ):
            variable.trace_add("write", lambda *_args: self._on_visual_changed())
        self._bind_mousewheel_recursive(art_content, self._scroll_editor_options)

    def _on_editor_options_content_configure(self, _event=None) -> None:
        if not hasattr(self, "editor_options_canvas"):
            return
        bbox = self.editor_options_canvas.bbox("all")
        if bbox is not None:
            self.editor_options_canvas.configure(scrollregion=bbox)

    def _on_editor_options_canvas_configure(self, event) -> None:
        if not hasattr(self, "editor_options_canvas") or not hasattr(self, "editor_options_window"):
            return
        self.editor_options_canvas.itemconfigure(self.editor_options_window, width=max(1, event.width))

    def _scroll_editor_options(self, event):
        if not hasattr(self, "editor_options_canvas"):
            return "break"
        if getattr(event, "num", None) == 4:
            units = -3
        elif getattr(event, "num", None) == 5:
            units = 3
        else:
            delta = getattr(event, "delta", 0)
            if delta == 0:
                return "break"
            units = -3 if delta > 0 else 3
        self.editor_options_canvas.yview_scroll(units, "units")
        return "break"

    def _asset_row(self, parent, label, variable, selected_command, import_command):
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=3)
        ttk.Label(row, text=label, width=7).pack(side="left")
        combo = ttk.Combobox(row, textvariable=variable, state="readonly")
        combo.pack(side="left", fill="x", expand=True)
        combo.bind("<<ComboboxSelected>>", selected_command)
        ttk.Button(row, text="导入…", width=7, command=import_command).pack(side="left", padx=(6, 0))
        return combo

    def _scale_row(self, parent, label, variable, start, end) -> None:
        row = ttk.Frame(parent)
        row.pack(fill="x", pady=2)
        ttk.Label(row, text=label, width=6).pack(side="left")
        ttk.Scale(row, variable=variable, from_=start, to=end, command=lambda _v: self._on_visual_changed()).pack(
            side="left", fill="x", expand=True
        )
        entry = ttk.Entry(row, textvariable=variable, width=7)
        entry.pack(side="left", padx=(6, 0))
        entry.bind("<KeyRelease>", lambda _e: self._on_visual_changed())

    def reload_cards(self) -> None:
        previous = self.current_card_id
        self._commit_form_to_memory()
        try:
            self.cards = core.load_editor_cards()
        except Exception as exc:
            self.cards = []
            messagebox.showerror("卡牌总表错误", str(exc))
        self.card_by_id = {card.card_id: card for card in self.cards}
        if not hasattr(self, "card_list"):
            return
        self.card_list.delete(0, "end")
        for card in self.cards:
            suffix = " ✓" if card.card_id in self.visuals and self.visuals[card.card_id].frame_path else ""
            prefix = f"{card.card_number:02d} " if card.card_number > 0 else ""
            cost_text = "?" if card.base_cost is None else str(card.base_cost)
            warning = " ⚠" if card.needs_confirmation else ""
            self.card_list.insert(
                "end",
                f"{prefix}{card.display_name}  [{cost_text}费]{warning}{suffix}",
            )
        if self.cards:
            index = next((i for i, card in enumerate(self.cards) if card.card_id == previous), 0)
            self.card_list.selection_set(index)
            self.card_list.activate(index)
            self._select_card(self.cards[index].card_id)

    def refresh_asset_choices(self) -> None:
        core.ensure_dirs()
        self.frame_assets = self._asset_map(core.FRAME_DIR)
        self.icon_assets = self._asset_map(core.ICON_DIR)
        if hasattr(self, "frame_combo"):
            self.frame_combo["values"] = [""] + list(self.frame_assets)
            self.icon_combo["values"] = [""] + list(self.icon_assets)
            if self.current_card_id:
                self._load_config_to_form(self._get_or_create_config(self.current_card_id))

    def _asset_map(self, root: Path) -> dict[str, Path]:
        return {
            path.relative_to(root).as_posix(): path
            for path in sorted(root.rglob("*.png"))
        }

    def _on_card_selected(self, _event=None) -> None:
        selection = self.card_list.curselection()
        if not selection:
            return
        self._commit_form_to_memory()
        self._select_card(self.cards[selection[0]].card_id)

    def _select_card(self, card_id: str) -> None:
        card = self.card_by_id.get(card_id)
        if card is None:
            return
        self.current_card_id = card_id
        number_prefix = f"{card.card_number:02d} " if card.card_number > 0 else ""
        self.info_name.configure(text=f"卡名：{number_prefix}{card.display_name}")
        self.info_cost.configure(
            text="费用：未定" if card.base_cost is None else f"费用：{card.base_cost}"
        )
        if card.category_label:
            self.info_tags.configure(text=f"类别：{card.category_label}")
        else:
            self.info_tags.configure(text="标签：" + (", ".join(card.tags) if card.tags else "无"))
        self.info_desc.configure(text=f"描述：{card.description}")
        visual_line = f"PNG：{card.visual_key}.png\n" if card.visual_key else ""
        self.card_source_label.configure(
            text=f"{visual_line}{card.card_id}\n{card.source_path}"
        )
        self._load_config_to_form(self._get_or_create_config(card_id))
        self.render_preview()

    def _get_or_create_config(self, card_id: str) -> core.VisualConfig:
        if card_id not in self.visuals:
            self.visuals[card_id] = core.VisualConfig(card_id=card_id)
        return self.visuals[card_id]

    def _display_name_for_asset(self, saved_path: str, root: Path) -> str:
        if not saved_path:
            return ""
        resolved = core.resolve_saved_path(saved_path)
        if resolved is None:
            return ""
        try:
            return resolved.relative_to(root).as_posix()
        except ValueError:
            return resolved.name

    def _load_config_to_form(self, config: core.VisualConfig) -> None:
        self._loading_form = True
        self.frame_var.set(self._display_name_for_asset(config.frame_path, core.FRAME_DIR))
        self.icon_var.set(self._display_name_for_asset(config.icon_path, core.ICON_DIR))
        self.frame_x_var.set(config.frame_x)
        self.frame_y_var.set(config.frame_y)
        self.frame_scale_var.set(config.frame_scale)
        self.icon_x_var.set(config.icon_x)
        self.icon_y_var.set(config.icon_y)
        self.icon_scale_var.set(config.icon_scale)
        self.icon_rotation_var.set(config.icon_rotation)
        self.title_y_var.set(config.title_y)
        self.desc_y_var.set(config.description_y)
        self.cost_x_var.set(config.cost_x)
        self.cost_y_var.set(config.cost_y)
        self.title_size_var.set(config.title_font_size)
        self.desc_size_var.set(config.description_font_size)
        self.cost_size_var.set(config.cost_font_size)
        self.text_width_var.set(config.text_width)
        self._loading_form = False

    def _commit_form_to_memory(self) -> None:
        if not self.current_card_id or self._loading_form:
            return
        config = self._get_or_create_config(self.current_card_id)
        frame_name = self.frame_var.get().strip()
        icon_name = self.icon_var.get().strip()
        frame_path = self.frame_assets.get(frame_name)
        icon_path = self.icon_assets.get(icon_name)
        config.frame_path = core.path_to_project_relative(frame_path) if frame_path else (config.frame_path if frame_name else "")
        config.icon_path = core.path_to_project_relative(icon_path) if icon_path else (config.icon_path if icon_name else "")
        config.frame_x = self._safe_int(self.frame_x_var.get(), config.frame_x)
        config.frame_y = self._safe_int(self.frame_y_var.get(), config.frame_y)
        config.frame_scale = self._safe_float(self.frame_scale_var.get(), config.frame_scale, 0.2, 2.0)
        config.icon_x = self._safe_int(self.icon_x_var.get(), config.icon_x)
        config.icon_y = self._safe_int(self.icon_y_var.get(), config.icon_y)
        config.icon_scale = self._safe_float(self.icon_scale_var.get(), config.icon_scale, 0.05, 2.5)
        config.icon_rotation = self._safe_float(self.icon_rotation_var.get(), config.icon_rotation, -360, 360)
        config.title_y = self._safe_int(self.title_y_var.get(), config.title_y)
        config.description_y = self._safe_int(self.desc_y_var.get(), config.description_y)
        config.cost_x = self._safe_int(self.cost_x_var.get(), config.cost_x)
        config.cost_y = self._safe_int(self.cost_y_var.get(), config.cost_y)
        config.title_font_size = self._safe_int(self.title_size_var.get(), config.title_font_size, 8, 96)
        config.description_font_size = self._safe_int(self.desc_size_var.get(), config.description_font_size, 8, 72)
        config.cost_font_size = self._safe_int(self.cost_size_var.get(), config.cost_font_size, 8, 96)
        config.text_width = self._safe_int(self.text_width_var.get(), config.text_width, 80, 400)

    def _safe_int(self, value, fallback: int, low: int = -1000, high: int = 1000) -> int:
        try:
            return max(low, min(high, int(float(value))))
        except (TypeError, ValueError, tk.TclError):
            return fallback

    def _safe_float(self, value, fallback: float, low: float, high: float) -> float:
        try:
            return max(low, min(high, float(value)))
        except (TypeError, ValueError, tk.TclError):
            return fallback

    def _on_visual_changed(self) -> None:
        if self._loading_form:
            return
        self._commit_form_to_memory()
        self._schedule_preview()

    def _schedule_preview(self, delay_ms: int = 45) -> None:
        if self.preview_after_id is not None:
            try:
                self.after_cancel(self.preview_after_id)
            except tk.TclError:
                pass
        self.preview_after_id = self.after(delay_ms, self._run_scheduled_preview)

    def _run_scheduled_preview(self) -> None:
        self.preview_after_id = None
        self.render_preview()

    def _on_frame_combo(self, _event=None) -> None:
        self._on_visual_changed()

    def _on_icon_combo(self, _event=None) -> None:
        self._on_visual_changed()

    def _import_single_asset(self, kind: str) -> None:
        target_dir = core.FRAME_DIR if kind == "frame" else core.ICON_DIR
        selected = filedialog.askopenfilename(
            title="选择卡框图片" if kind == "frame" else "选择图标图片",
            filetypes=IMAGE_TYPES,
        )
        if not selected:
            return
        source = Path(selected)
        target = target_dir / source.name
        if source.resolve() != target.resolve():
            if target.exists() and not messagebox.askyesno("覆盖素材", f"{target.name} 已存在，是否覆盖？"):
                return
            shutil.copy2(source, target)
        self.refresh_asset_choices()
        if kind == "frame":
            self.frame_var.set(target.relative_to(core.FRAME_DIR).as_posix())
        else:
            self.icon_var.set(target.relative_to(core.ICON_DIR).as_posix())
        self._on_visual_changed()

    def render_preview(self) -> None:
        if not self.current_card_id or not hasattr(self, "preview_canvas"):
            return
        card = self.card_by_id.get(self.current_card_id)
        if card is None:
            return
        self._commit_form_to_memory()
        config = self.visuals[self.current_card_id]
        try:
            image = core.compose_card(card, config)
        except Exception as exc:
            self.editor_status.configure(text=f"预览失败：{exc}")
            return
        canvas_w = max(100, self.preview_canvas.winfo_width())
        canvas_h = max(100, self.preview_canvas.winfo_height())
        scale = min((canvas_w - 30) / image.width, (canvas_h - 30) / image.height, 1.25)
        scale = max(0.1, scale)
        display_size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
        display = image.resize(display_size, Image.Resampling.LANCZOS)
        self.preview_photo = ImageTk.PhotoImage(display)
        self.preview_scale = scale
        ox = (canvas_w - display_size[0]) // 2
        oy = (canvas_h - display_size[1]) // 2
        self.preview_canvas.delete("all")
        self.preview_canvas.create_rectangle(
            ox - 1, oy - 1, ox + display_size[0] + 1, oy + display_size[1] + 1, outline="#6a6d73"
        )
        self.preview_canvas.create_image(ox, oy, image=self.preview_photo, anchor="nw")
        frame_state = "已选卡框" if config.frame_path else "未选卡框（占位框）"
        icon_state = "已选图标" if config.icon_path else "未选图标"
        self.editor_status.configure(text=f"{frame_state} · {icon_state} · 输出 {core.CARD_SIZE[0]}×{core.CARD_SIZE[1]}")

    def _preview_drag_start(self, event) -> None:
        if self.current_card_id:
            self.drag_start = (event.x, event.y)

    def _preview_drag_move(self, event) -> None:
        if not self.drag_start or not self.current_card_id:
            return
        dx = (event.x - self.drag_start[0]) / max(self.preview_scale, 0.01)
        dy = (event.y - self.drag_start[1]) / max(self.preview_scale, 0.01)
        self.drag_start = (event.x, event.y)
        self._loading_form = True
        if self.preview_drag_target_var.get() == "cost":
            self.cost_x_var.set(
                self._safe_float(self.cost_x_var.get(), 355, -999, 999) + dx
            )
            self.cost_y_var.set(
                self._safe_float(self.cost_y_var.get(), 55, -999, 999) + dy
            )
        else:
            self.icon_x_var.set(self._safe_float(self.icon_x_var.get(), 0, -999, 999) + dx)
            self.icon_y_var.set(self._safe_float(self.icon_y_var.get(), 0, -999, 999) + dy)
        self._loading_form = False
        self._commit_form_to_memory()
        self._schedule_preview(16)

    def _preview_drag_end(self, _event) -> None:
        self.drag_start = None

    def reset_layout(self) -> None:
        if not self.current_card_id:
            return
        old = self._get_or_create_config(self.current_card_id)
        default = core.VisualConfig(card_id=self.current_card_id, frame_path=old.frame_path, icon_path=old.icon_path)
        self.visuals[self.current_card_id] = default
        self._load_config_to_form(default)
        self.render_preview()

    def save_visuals(self) -> None:
        self._commit_form_to_memory()
        core.save_visual_db(self.visuals)
        self.reload_cards()
        self.editor_status.configure(text=f"视觉配置已保存：{core.VISUAL_DB_PATH}")

    def export_current(self) -> None:
        if not self.current_card_id:
            return
        self._commit_form_to_memory()
        selected = filedialog.askdirectory(title="选择 PNG 导出目录")
        if not selected:
            return
        try:
            output = core.export_card(
                self.card_by_id[self.current_card_id],
                self.visuals[self.current_card_id],
                Path(selected),
            )
        except Exception as exc:
            messagebox.showerror("导出失败", str(exc))
            return
        messagebox.showinfo("导出完成", f"已生成：\n{output}")

    def sync_all(self) -> None:
        self._commit_form_to_memory()
        core.save_visual_db(self.visuals)
        try:
            exported, skipped = core.sync_cards_to_godot(self.cards, self.visuals)
        except Exception as exc:
            messagebox.showerror("同步失败", str(exc))
            return
        self.reload_cards()
        text = f"已同步 {len(exported)} 张卡牌到：\n{core.GENERATED_DIR}"
        if skipped:
            text += f"\n\n未配置卡框而跳过：{len(skipped)} 张"
        messagebox.showinfo("卡牌外观生成完成", text)

    def _build_atlas_tab(self) -> None:
        paned = ttk.Panedwindow(self.atlas_tab, orient="horizontal")
        paned.pack(fill="both", expand=True)
        left = ttk.Frame(paned, padding=8)
        right = ttk.Frame(paned, width=360)
        paned.add(left, weight=4)
        paned.add(right, weight=2)

        # 右侧工具内容会随着切片预览、保存选项继续向下延伸。
        # 使用 Canvas + Scrollbar 承载整个功能区，避免小窗口/高 DPI 下底部控件被裁掉。
        right.rowconfigure(0, weight=1)
        right.columnconfigure(0, weight=1)
        self.atlas_options_canvas = tk.Canvas(
            right,
            highlightthickness=0,
            borderwidth=0,
            background=self.cget("background"),
        )
        options_scrollbar = ttk.Scrollbar(
            right,
            orient="vertical",
            command=self.atlas_options_canvas.yview,
        )
        self.atlas_options_canvas.configure(yscrollcommand=options_scrollbar.set)
        self.atlas_options_canvas.grid(row=0, column=0, sticky="nsew")
        options_scrollbar.grid(row=0, column=1, sticky="ns")

        right_content = ttk.Frame(self.atlas_options_canvas, padding=(8, 8, 6, 8))
        self.atlas_options_window = self.atlas_options_canvas.create_window(
            (0, 0),
            window=right_content,
            anchor="nw",
        )
        right_content.bind("<Configure>", self._on_atlas_options_content_configure)
        self.atlas_options_canvas.bind("<Configure>", self._on_atlas_options_canvas_configure)

        top = ttk.Frame(left)
        top.pack(fill="x")
        ttk.Button(top, text="导入图集…", command=self.import_atlas).pack(side="left")
        self.atlas_path_label = ttk.Label(top, text="尚未选择图集", foreground="#666666")
        self.atlas_path_label.pack(side="left", padx=(10, 0))
        self.atlas_canvas = tk.Canvas(left, bg="#202226", highlightthickness=1, highlightbackground="#55585f")
        self.atlas_canvas.pack(fill="both", expand=True, pady=(8, 0))
        self.atlas_canvas.bind("<Configure>", lambda _e: self.render_atlas())
        self.atlas_canvas.bind("<ButtonPress-1>", self._atlas_press)
        self.atlas_canvas.bind("<B1-Motion>", self._atlas_drag)
        self.atlas_canvas.bind("<ButtonRelease-1>", self._atlas_release)

        settings = ttk.LabelFrame(right_content, text="切割设置", style="Section.TLabelframe")
        settings.pack(fill="x")
        self.atlas_rows_var = tk.IntVar(value=4)
        self.atlas_cols_var = tk.IntVar(value=4)
        self.atlas_padding_x_var = tk.IntVar(value=0)
        self.atlas_padding_y_var = tk.IntVar(value=0)
        self.atlas_gap_x_var = tk.IntVar(value=0)
        self.atlas_gap_y_var = tk.IntVar(value=0)
        self.atlas_trim_var = tk.BooleanVar(value=True)
        self.atlas_black_var = tk.BooleanVar(value=False)
        self.atlas_normalize_var = tk.BooleanVar(value=True)
        self.atlas_normalize_size_var = tk.IntVar(value=256)

        fields = [
            ("行", self.atlas_rows_var, 1, 20),
            ("列", self.atlas_cols_var, 1, 20),
            ("左右外边距", self.atlas_padding_x_var, 0, 1000),
            ("上下外边距", self.atlas_padding_y_var, 0, 1000),
            ("横向间隔", self.atlas_gap_x_var, 0, 500),
            ("纵向间隔", self.atlas_gap_y_var, 0, 500),
        ]
        for label, var, lo, hi in fields:
            row = ttk.Frame(settings)
            row.pack(fill="x", pady=2)
            ttk.Label(row, text=label).pack(side="left")
            spin = ttk.Spinbox(
                row,
                textvariable=var,
                from_=lo,
                to=hi,
                width=8,
                command=self._schedule_crop_reset,
            )
            spin.pack(side="right")
            spin.bind("<KeyRelease>", lambda _e: self._schedule_crop_reset())
            spin.bind("<Return>", lambda _e: self._schedule_crop_reset(0))
            spin.bind("<FocusOut>", lambda _e: self._schedule_crop_reset(0))
        self.atlas_trim_check = ttk.Checkbutton(
            settings,
            text="裁掉透明空边",
            variable=self.atlas_trim_var,
            command=self._schedule_atlas_tiles,
        )
        self.atlas_trim_check.pack(anchor="w", pady=(5, 0))
        ttk.Checkbutton(
            settings,
            text="把近黑色背景转透明（AI 图集黑底时用）",
            variable=self.atlas_black_var,
            command=self._schedule_atlas_tiles,
        ).pack(anchor="w")
        normalize_row = ttk.Frame(settings)
        normalize_row.pack(fill="x", pady=(4, 0))
        self.atlas_normalize_check = ttk.Checkbutton(
            normalize_row,
            text="统一透明画布",
            variable=self.atlas_normalize_var,
            command=self._schedule_atlas_tiles,
        )
        self.atlas_normalize_check.pack(side="left")
        self.atlas_normalize_spin = ttk.Spinbox(
            normalize_row,
            textvariable=self.atlas_normalize_size_var,
            from_=64,
            to=1024,
            width=7,
            command=self._schedule_atlas_tiles,
        )
        self.atlas_normalize_spin.pack(side="right")
        self.atlas_frame_mode_hint = ttk.Label(
            settings,
            text="",
            foreground="#8a5a00",
            wraplength=320,
        )
        self.atlas_frame_mode_hint.pack(fill="x", pady=(4, 0))
        ttk.Button(settings, text="按当前网格重置全部裁剪框", command=self.reset_crop_boxes).pack(fill="x", pady=(7, 0))
        ttk.Button(
            settings,
            text="自动检测并对齐卡框网格",
            command=self.auto_align_frame_grid,
        ).pack(fill="x", pady=(6, 0))
        ttk.Label(
            settings,
            text="改变行/列/边距/间隔会自动重建框；之后每个框可独立拖动，拖边/四角可单独缩放。",
            foreground="#666666",
            wraplength=320,
        ).pack(fill="x", pady=(5, 0))

        selected = ttk.LabelFrame(right_content, text="当前切片", style="Section.TLabelframe")
        selected.pack(fill="x", pady=(8, 0))
        self.tile_preview = tk.Canvas(selected, width=300, height=270, bg="#202226", highlightthickness=0)
        self.tile_preview.pack(fill="x")
        self.tile_index_label = ttk.Label(selected, text="切片：-")
        self.tile_index_label.pack(anchor="w", pady=(4, 0))

        output = ttk.LabelFrame(right_content, text="保存到素材库", style="Section.TLabelframe")
        output.pack(fill="x", pady=(8, 0))
        self.atlas_kind_var = tk.StringVar(value="icon")
        kind_row = ttk.Frame(output)
        kind_row.pack(fill="x")
        ttk.Radiobutton(
            kind_row,
            text="图标",
            value="icon",
            variable=self.atlas_kind_var,
            command=self._on_atlas_kind_changed,
        ).pack(side="left")
        ttk.Radiobutton(
            kind_row,
            text="卡框",
            value="frame",
            variable=self.atlas_kind_var,
            command=self._on_atlas_kind_changed,
        ).pack(side="left", padx=(12, 0))
        name_row = ttk.Frame(output)
        name_row.pack(fill="x", pady=(6, 0))
        ttk.Label(name_row, text="当前名称").pack(side="left")
        self.tile_name_var = tk.StringVar(value="icon_01")
        ttk.Entry(name_row, textvariable=self.tile_name_var).pack(side="left", fill="x", expand=True, padx=(8, 0))
        prefix_row = ttk.Frame(output)
        prefix_row.pack(fill="x", pady=(6, 0))
        ttk.Label(prefix_row, text="批量前缀").pack(side="left")
        self.tile_prefix_var = tk.StringVar(value="icon")
        ttk.Entry(prefix_row, textvariable=self.tile_prefix_var).pack(side="left", fill="x", expand=True, padx=(8, 0))
        ttk.Button(output, text="保存当前切片", command=self.save_selected_tile).pack(fill="x", pady=(8, 0))
        ttk.Button(output, text="保存全部切片", command=self.save_all_tiles).pack(fill="x", pady=(6, 0))
        ttk.Button(
            output,
            text="打开当前素材目录",
            command=lambda: self._open_folder(self._tile_destination()),
        ).pack(fill="x", pady=(6, 0))
        self.atlas_status = ttk.Label(right_content, text="卡框图通常 2×3；技能图标图通常 4×4。", wraplength=330)
        self.atlas_status.pack(fill="x", pady=(8, 0))
        self._bind_mousewheel_recursive(right_content, self._scroll_atlas_options)

    def _on_atlas_options_content_configure(self, _event=None) -> None:
        if not hasattr(self, "atlas_options_canvas"):
            return
        bbox = self.atlas_options_canvas.bbox("all")
        if bbox is not None:
            self.atlas_options_canvas.configure(scrollregion=bbox)

    def _on_atlas_options_canvas_configure(self, event) -> None:
        if not hasattr(self, "atlas_options_canvas") or not hasattr(self, "atlas_options_window"):
            return
        self.atlas_options_canvas.itemconfigure(self.atlas_options_window, width=max(1, event.width))

    def _bind_mousewheel_recursive(self, widget, callback) -> None:
        widget.bind("<MouseWheel>", callback, add="+")
        widget.bind("<Button-4>", callback, add="+")
        widget.bind("<Button-5>", callback, add="+")
        for child in widget.winfo_children():
            self._bind_mousewheel_recursive(child, callback)

    def _scroll_atlas_options(self, event):
        if not hasattr(self, "atlas_options_canvas"):
            return "break"
        if getattr(event, "num", None) == 4:
            units = -3
        elif getattr(event, "num", None) == 5:
            units = 3
        else:
            delta = getattr(event, "delta", 0)
            if delta == 0:
                return "break"
            units = -3 if delta > 0 else 3
        self.atlas_options_canvas.yview_scroll(units, "units")
        return "break"

    def import_atlas(self) -> None:
        selected = filedialog.askopenfilename(title="选择 AI 图集", filetypes=IMAGE_TYPES)
        if not selected:
            return
        try:
            copied = core.copy_source_sheet(selected)
            self.atlas_source = copied
            self.atlas_source_image = Image.open(copied).convert("RGBA")
            self.atlas_render_key = None
        except Exception as exc:
            messagebox.showerror("图集读取失败", str(exc))
            return
        self.atlas_path_label.configure(text=str(copied))
        self.atlas_selected_index = 0
        self.reset_crop_boxes()

    def _grid_options(self) -> dict:
        return {
            "rows": self._safe_int(self.atlas_rows_var.get(), 1, 1, 50),
            "cols": self._safe_int(self.atlas_cols_var.get(), 1, 1, 50),
            "padding_x": self._safe_int(self.atlas_padding_x_var.get(), 0, 0, 5000),
            "padding_y": self._safe_int(self.atlas_padding_y_var.get(), 0, 0, 5000),
            "gap_x": self._safe_int(self.atlas_gap_x_var.get(), 0, 0, 5000),
            "gap_y": self._safe_int(self.atlas_gap_y_var.get(), 0, 0, 5000),
        }

    def _postprocess_options(self) -> dict:
        if hasattr(self, "atlas_kind_var") and self.atlas_kind_var.get() == "frame":
            return {
                "trim": False,
                "make_black_transparent": self.atlas_black_var.get(),
                "normalize_to": None,
            }
        normalize_to = None
        if self.atlas_normalize_var.get():
            size = self._safe_int(self.atlas_normalize_size_var.get(), 256, 32, 2048)
            normalize_to = (size, size)
        return {
            "trim": self.atlas_trim_var.get(),
            "make_black_transparent": self.atlas_black_var.get(),
            "normalize_to": normalize_to,
        }

    def _on_atlas_kind_changed(self) -> None:
        is_frame = self.atlas_kind_var.get() == "frame"
        state = "disabled" if is_frame else "normal"
        if hasattr(self, "atlas_trim_check"):
            self.atlas_trim_check.configure(state=state)
        if hasattr(self, "atlas_normalize_check"):
            self.atlas_normalize_check.configure(state=state)
        if hasattr(self, "atlas_normalize_spin"):
            self.atlas_normalize_spin.configure(state=state)
        if hasattr(self, "atlas_frame_mode_hint"):
            self.atlas_frame_mode_hint.configure(
                text=(
                    "卡框固定坐标模式：不逐张裁透明边、不转正方形；"
                    "所有网格单元使用同一坐标映射到 420×600。"
                    if is_frame
                    else ""
                )
            )
        if is_frame and self.atlas_source_image is not None:
            self.reset_crop_boxes()
        else:
            self.refresh_atlas_tiles()

    def _detect_frame_grid_boxes(self) -> list[list[float]]:
        if self.atlas_source_image is None:
            return []
        options = self._grid_options()
        return core.detect_uniform_grid_boxes(
            self.atlas_source_image,
            options["rows"],
            options["cols"],
            make_black_transparent=self.atlas_black_var.get(),
            padding=2,
        )

    def auto_align_frame_grid(self) -> None:
        if self.atlas_source_image is None:
            return
        try:
            boxes = self._detect_frame_grid_boxes()
        except Exception as exc:
            self.atlas_status.configure(text=f"自动检测卡框网格失败：{exc}")
            return
        if not boxes:
            return
        self.crop_boxes = boxes
        self.atlas_selected_index = min(
            self.atlas_selected_index,
            max(0, len(self.crop_boxes) - 1),
        )
        self.refresh_atlas_tiles()
        width = self.crop_boxes[0][2] - self.crop_boxes[0][0]
        height = self.crop_boxes[0][3] - self.crop_boxes[0][1]
        self.atlas_status.configure(
            text=(
                f"卡框网格已自动对齐：{len(self.crop_boxes)} 格，"
                f"统一裁剪尺寸约 {width:.0f}×{height:.0f}。"
            )
        )

    def reset_crop_boxes(self) -> None:
        if self.atlas_source_image is None:
            return
        is_frame = hasattr(self, "atlas_kind_var") and self.atlas_kind_var.get() == "frame"
        try:
            if is_frame:
                self.crop_boxes = self._detect_frame_grid_boxes()
            else:
                self.crop_boxes = core.grid_boxes(
                    self.atlas_source_image.size,
                    **self._grid_options(),
                )
        except Exception as exc:
            if not is_frame:
                self.atlas_status.configure(text=f"网格参数错误：{exc}")
                return
            self.crop_boxes = core.grid_boxes(
                self.atlas_source_image.size,
                **self._grid_options(),
            )
            self.atlas_status.configure(
                text=f"自动对齐失败，已退回等分网格：{exc}"
            )
        self.atlas_selected_index = min(self.atlas_selected_index, max(0, len(self.crop_boxes) - 1))
        self.refresh_atlas_tiles()

    def _schedule_crop_reset(self, delay_ms: int = 180) -> None:
        if self.atlas_source_image is None:
            return
        if self.grid_reset_after_id is not None:
            try:
                self.after_cancel(self.grid_reset_after_id)
            except tk.TclError:
                pass
        self.grid_reset_after_id = self.after(delay_ms, self._run_scheduled_crop_reset)

    def _run_scheduled_crop_reset(self) -> None:
        self.grid_reset_after_id = None
        self.reset_crop_boxes()

    def _schedule_atlas_tiles(self, delay_ms: int = 70) -> None:
        if self.atlas_after_id is not None:
            try:
                self.after_cancel(self.atlas_after_id)
            except tk.TclError:
                pass
        self.atlas_after_id = self.after(delay_ms, self._run_scheduled_atlas_tiles)

    def _run_scheduled_atlas_tiles(self) -> None:
        self.atlas_after_id = None
        self.refresh_atlas_tiles()

    def refresh_atlas_tiles(self) -> None:
        if self.atlas_source_image is None:
            return
        if not self.crop_boxes:
            self.reset_crop_boxes()
            return
        try:
            self.atlas_tiles = core.crop_boxes(
                self.atlas_source_image,
                self.crop_boxes,
                **self._postprocess_options(),
            )
        except Exception as exc:
            self.atlas_status.configure(text=f"切割参数错误：{exc}")
            return
        if self.atlas_selected_index >= len(self.atlas_tiles):
            self.atlas_selected_index = 0
        self.atlas_status.configure(text=f"已得到 {len(self.atlas_tiles)} 个切片。点击左侧图集选择切片。")
        self._update_tile_name_default()
        self.render_atlas()
        self.render_selected_tile()

    def render_atlas(self) -> None:
        if self.atlas_source_image is None or not hasattr(self, "atlas_canvas"):
            return
        canvas_w = max(100, self.atlas_canvas.winfo_width())
        canvas_h = max(100, self.atlas_canvas.winfo_height())
        image = self.atlas_source_image
        scale = min((canvas_w - 20) / image.width, (canvas_h - 20) / image.height)
        scale = max(0.05, scale)
        size = (max(1, round(image.width * scale)), max(1, round(image.height * scale)))
        render_key = (id(image), size[0], size[1])
        if self.atlas_photo is None or self.atlas_render_key != render_key:
            display = image.resize(size, Image.Resampling.LANCZOS)
            self.atlas_photo = ImageTk.PhotoImage(display)
            self.atlas_render_key = render_key
        ox = (canvas_w - size[0]) // 2
        oy = (canvas_h - size[1]) // 2
        self.atlas_draw_box = (ox, oy, ox + size[0], oy + size[1])
        self.atlas_scale = scale
        self.atlas_origin = (float(ox), float(oy))
        self.atlas_canvas.delete("all")
        self.atlas_canvas.create_image(ox, oy, image=self.atlas_photo, anchor="nw")
        for index, box in enumerate(self.crop_boxes):
            x1 = ox + box[0] * scale
            y1 = oy + box[1] * scale
            x2 = ox + box[2] * scale
            y2 = oy + box[3] * scale
            color = "#ffd166" if index == self.atlas_selected_index else "#58a6ff"
            width = 3 if index == self.atlas_selected_index else 1
            self.atlas_canvas.create_rectangle(x1, y1, x2, y2, outline=color, width=width)
            self.atlas_canvas.create_text(x1 + 7, y1 + 7, text=str(index + 1), fill=color, anchor="nw")
            if index == self.atlas_selected_index:
                self._draw_crop_handles(x1, y1, x2, y2)

    def _draw_crop_handles(self, x1: float, y1: float, x2: float, y2: float) -> None:
        radius = 5
        points = [
            (x1, y1), ((x1 + x2) / 2, y1), (x2, y1),
            (x2, (y1 + y2) / 2), (x2, y2), ((x1 + x2) / 2, y2),
            (x1, y2), (x1, (y1 + y2) / 2),
        ]
        for x, y in points:
            self.atlas_canvas.create_rectangle(
                x - radius, y - radius, x + radius, y + radius,
                fill="#ffd166", outline="#2a2a2a",
            )

    def _canvas_to_source(self, x: float, y: float) -> tuple[float, float]:
        ox, oy = self.atlas_origin
        return (
            (x - ox) / max(self.atlas_scale, 0.001),
            (y - oy) / max(self.atlas_scale, 0.001),
        )

    def _hit_crop_box(self, sx: float, sy: float) -> tuple[int, str] | None:
        if not self.crop_boxes:
            return None
        tolerance = 9.0 / max(self.atlas_scale, 0.05)
        order = [self.atlas_selected_index] + [
            i for i in range(len(self.crop_boxes)) if i != self.atlas_selected_index
        ]
        for index in order:
            left, top, right, bottom = self.crop_boxes[index]
            if not (left - tolerance <= sx <= right + tolerance and top - tolerance <= sy <= bottom + tolerance):
                continue
            near_l = abs(sx - left) <= tolerance
            near_r = abs(sx - right) <= tolerance
            near_t = abs(sy - top) <= tolerance
            near_b = abs(sy - bottom) <= tolerance
            if near_l and near_t:
                return index, "nw"
            if near_r and near_t:
                return index, "ne"
            if near_r and near_b:
                return index, "se"
            if near_l and near_b:
                return index, "sw"
            if near_t and left <= sx <= right:
                return index, "n"
            if near_r and top <= sy <= bottom:
                return index, "e"
            if near_b and left <= sx <= right:
                return index, "s"
            if near_l and top <= sy <= bottom:
                return index, "w"
            if left <= sx <= right and top <= sy <= bottom:
                return index, "move"
        return None

    def _atlas_press(self, event) -> None:
        if self.atlas_source_image is None:
            return
        sx, sy = self._canvas_to_source(event.x, event.y)
        hit = self._hit_crop_box(sx, sy)
        if hit is None:
            return
        self.atlas_selected_index, self.atlas_drag_mode = hit
        self.atlas_drag_start = (sx, sy)
        self.atlas_drag_original = list(self.crop_boxes[self.atlas_selected_index])
        self._update_tile_name_default()
        self.render_atlas()
        self.render_selected_tile()

    def _atlas_drag(self, event) -> None:
        if (
            self.atlas_source_image is None
            or self.atlas_drag_start is None
            or self.atlas_drag_original is None
            or self.atlas_drag_mode is None
        ):
            return
        sx, sy = self._canvas_to_source(event.x, event.y)
        dx = sx - self.atlas_drag_start[0]
        dy = sy - self.atlas_drag_start[1]
        left, top, right, bottom = self.atlas_drag_original
        width = right - left
        height = bottom - top
        image_w, image_h = self.atlas_source_image.size
        mode = self.atlas_drag_mode

        if mode == "move":
            left = min(max(0.0, left + dx), max(0.0, image_w - width))
            top = min(max(0.0, top + dy), max(0.0, image_h - height))
            right = left + width
            bottom = top + height
        else:
            if "w" in mode:
                left = min(max(0.0, left + dx), right - 8.0)
            if "e" in mode:
                right = max(min(float(image_w), right + dx), left + 8.0)
            if "n" in mode:
                top = min(max(0.0, top + dy), bottom - 8.0)
            if "s" in mode:
                bottom = max(min(float(image_h), bottom + dy), top + 8.0)

        self.crop_boxes[self.atlas_selected_index] = [left, top, right, bottom]
        self.render_atlas()
        self._schedule_atlas_tiles(55)

    def _atlas_release(self, _event) -> None:
        if self.atlas_drag_mode is not None:
            self.refresh_atlas_tiles()
        self.atlas_drag_mode = None
        self.atlas_drag_start = None
        self.atlas_drag_original = None

    def _update_tile_name_default(self) -> None:
        prefix = self.tile_prefix_var.get().strip() if hasattr(self, "tile_prefix_var") else "icon"
        if not prefix:
            prefix = "icon"
        if hasattr(self, "tile_name_var"):
            self.tile_name_var.set(f"{prefix}_{self.atlas_selected_index + 1:02d}")

    def render_selected_tile(self) -> None:
        self.tile_preview.delete("all")
        if not self.atlas_tiles:
            self.tile_index_label.configure(text="切片：-")
            return
        tile = self._prepared_tile_for_output(self.atlas_tiles[self.atlas_selected_index])
        canvas_w, canvas_h = max(100, self.tile_preview.winfo_width() or 300), 270
        scale = min((canvas_w - 16) / tile.width, (canvas_h - 16) / tile.height)
        size = (max(1, round(tile.width * scale)), max(1, round(tile.height * scale)))
        display = tile.resize(size, Image.Resampling.LANCZOS)
        self.atlas_tile_photo = ImageTk.PhotoImage(display)
        self.tile_preview.create_image(canvas_w // 2, canvas_h // 2, image=self.atlas_tile_photo)
        self.tile_index_label.configure(
            text=(
                f"切片 {self.atlas_selected_index + 1}/{len(self.atlas_tiles)}"
                f" · 保存尺寸 {tile.width}×{tile.height}"
            )
        )

    def _prepared_tile_for_output(self, tile: Image.Image) -> Image.Image:
        if hasattr(self, "atlas_kind_var") and self.atlas_kind_var.get() == "frame":
            return core.map_frame_cell_to_card(tile)
        return tile

    def _tile_destination(self) -> Path:
        return core.FRAME_DIR if self.atlas_kind_var.get() == "frame" else core.ICON_DIR

    def _clean_asset_name(self, name: str, fallback: str) -> str:
        name = name.strip().replace(" ", "_")
        valid = "".join(ch for ch in name if ch.isalnum() or ch in "_-.")
        if not valid:
            valid = fallback
        if not valid.lower().endswith(".png"):
            valid += ".png"
        return valid

    def save_selected_tile(self) -> None:
        if not self.atlas_tiles:
            return
        dest_dir = self._tile_destination()
        dest_dir.mkdir(parents=True, exist_ok=True)
        name = self._clean_asset_name(self.tile_name_var.get(), f"slice_{self.atlas_selected_index + 1:02d}")
        output = dest_dir / name
        if output.exists() and not messagebox.askyesno("覆盖素材", f"{output.name} 已存在，是否覆盖？"):
            return
        self._prepared_tile_for_output(self.atlas_tiles[self.atlas_selected_index]).save(output, "PNG")
        self.refresh_asset_choices()
        self.atlas_status.configure(text=f"已保存：{output}")

    def save_all_tiles(self) -> None:
        if not self.atlas_tiles:
            return
        dest_dir = self._tile_destination()
        dest_dir.mkdir(parents=True, exist_ok=True)
        prefix = self.tile_prefix_var.get().strip() or ("frame" if self.atlas_kind_var.get() == "frame" else "icon")
        written = []
        for index, tile in enumerate(self.atlas_tiles, start=1):
            name = self._clean_asset_name(f"{prefix}_{index:02d}", f"slice_{index:02d}")
            output = dest_dir / name
            self._prepared_tile_for_output(tile).save(output, "PNG")
            written.append(output)
        self.refresh_asset_choices()
        self.atlas_status.configure(text=f"已保存 {len(written)} 个切片到：{dest_dir}")
        messagebox.showinfo("批量切割完成", f"已保存 {len(written)} 个 PNG。\n{dest_dir}")

    def _build_help_tab(self) -> None:
        text = tk.Text(
            self.help_tab,
            wrap="word",
            font=("Microsoft YaHei UI", 11),
            padx=24,
            pady=20,
            relief="flat",
        )
        text.pack(fill="both", expand=True)
        text.insert(
            "1.0",
            """第一版工作流

1. 图集切割器
   导入卡框/图标大图。卡框图可用 2 行 × 3 列，技能图通常 4 × 4。
   如果 AI 图片实际是黑底，勾选“把近黑色背景转透明”。
   图标建议统一透明画布 256×256。
   选择“卡框”后会自动进入固定坐标模式：逐张裁透明边和正方形归一化被禁用，
   每个网格单元直接使用同一坐标变换映射到 420×600，避免不同颜色卡框产生像素漂移。

2. 卡牌编辑器
   左侧只读加载 content/cards 下已有的 CardDef，用于取得卡名、费用和描述。
   选择卡框和主图标，拖动图标并调整缩放/旋转。
   卡名、费用和描述直接来自 CardDef。

   当前版本只做外观，不提供新建卡牌、技能/规则编辑或 CardDef 写回。

3. 生成游戏卡牌 PNG
   成品固定输出 420×600 PNG 到 assets/textures/cards/generated。
   visual_manifest.json 保存 card_id 到 res://PNG 的映射。

当前版本负责把散素材制作成正式游戏 PNG。
下一步可以新增 Godot CardView，让战斗手牌直接读取这些成品卡。
""",
        )
        text.configure(state="disabled")

    def _open_folder(self, path: Path) -> None:
        path.mkdir(parents=True, exist_ok=True)
        try:
            os.startfile(str(path))  # type: ignore[attr-defined]
        except AttributeError:
            subprocess.Popen(["explorer", str(path)])

    def _on_close(self) -> None:
        try:
            self._commit_form_to_memory()
            core.save_visual_db(self.visuals)
        finally:
            self.destroy()


def main() -> int:
    app = CardEditorApp()
    app.mainloop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
