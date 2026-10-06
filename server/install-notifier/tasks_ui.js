// Раздел «Задачи» админки: современный интерфейс уровня Linear / Tasklify.
// Канбан-доска, сводка метрик, компактный список, умная типографика карточек (заголовок + описание),
// прикрепление картинок с красивым превью, фильтры по версиям и приоритету, Drag & Drop + 1-click кнопки.

export const TASKS_NAV_HTML = `<button class="nav-item" data-feature="tasks"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M9 11l3 3L22 4"/><path d="M21 12v7a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11"/></svg><span>Задачи</span></button>`;

export const TASKS_VIEW_HTML = `
<div id="tasks-view" style="display:none">
  <style>
    .tasks-wrap {
      display: flex;
      flex-direction: column;
      gap: 18px;
      margin-bottom: 40px;
      font-family: inherit;
    }

    /* 1. Верхние KPI метрики (якоря прогресса) */
    .tasks-kpi-grid {
      display: grid;
      grid-template-columns: repeat(4, minmax(0, 1fr));
      gap: 12px;
    }
    .tasks-kpi-card {
      background: var(--card-bg);
      border-radius: 16px;
      padding: 16px 18px;
      display: flex;
      flex-direction: column;
      justify-content: space-between;
      border: 1px solid #EAECEF;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
      cursor: pointer;
      transition: all 0.15s ease;
      user-select: none;
    }
    .tasks-kpi-card:hover {
      transform: translateY(-1px);
      box-shadow: 0 4px 14px rgba(0, 0, 0, 0.05);
      border-color: #D1D5DB;
    }
    .tasks-kpi-card.active {
      border-color: var(--primary);
      box-shadow: 0 0 0 2px var(--primary-subtle);
    }
    .tasks-kpi-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 8px;
      margin-bottom: 8px;
    }
    .tasks-kpi-label {
      font-size: 12px;
      font-weight: 700;
      color: var(--text-muted);
      text-transform: uppercase;
      letter-spacing: 0.4px;
    }
    .tasks-kpi-icon {
      width: 28px;
      height: 28px;
      border-radius: 8px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 13px;
    }
    .tasks-kpi-value {
      font-size: 26px;
      font-weight: 800;
      letter-spacing: -0.6px;
      color: var(--text);
      line-height: 1.1;
      font-variant-numeric: tabular-nums;
    }
    .tasks-kpi-sub {
      font-size: 11.5px;
      color: var(--text-muted);
      margin-top: 5px;
      font-weight: 500;
    }

    /* 2. Тулбар: переключатели, поиск, фильтры */
    .tasks-toolbar {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      justify-content: space-between;
      gap: 12px;
      background: var(--card-bg);
      padding: 12px 16px;
      border-radius: 16px;
      border: 1px solid #EAECEF;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
    }
    .tasks-toolbar-left {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 10px;
      flex: 1 1 auto;
    }
    .tasks-toolbar-right {
      display: flex;
      align-items: center;
      gap: 10px;
      flex-shrink: 0;
    }

    .tasks-segmented {
      display: inline-flex;
      background: var(--surface-gray);
      border-radius: 10px;
      padding: 3px;
      gap: 2px;
    }
    .tasks-segmented button {
      border: none;
      background: transparent;
      border-radius: 8px;
      padding: 7px 13px;
      font: inherit;
      font-size: 13px;
      font-weight: 600;
      color: var(--text-light);
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.15s ease;
    }
    .tasks-segmented button.active {
      background: #FFFFFF;
      color: var(--text);
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
      font-weight: 700;
    }

    .tasks-search-wrap {
      position: relative;
      min-width: 220px;
      flex: 1 1 240px;
      max-width: 340px;
    }
    .tasks-search-wrap input {
      width: 100%;
      box-sizing: border-box;
      background: var(--surface-gray);
      border: 1px solid transparent;
      border-radius: 10px;
      padding: 8px 32px 8px 34px;
      font: inherit;
      font-size: 13px;
      color: var(--text);
      outline: none;
      transition: all 0.15s ease;
    }
    .tasks-search-wrap input:focus {
      background: #FFFFFF;
      border-color: var(--primary);
      box-shadow: 0 0 0 3px var(--primary-subtle);
    }
    .tasks-search-wrap .search-icon {
      position: absolute;
      left: 10px;
      top: 50%;
      transform: translateY(-50%);
      color: var(--text-muted);
      pointer-events: none;
    }
    .tasks-search-wrap .search-clear {
      position: absolute;
      right: 8px;
      top: 50%;
      transform: translateY(-50%);
      border: none;
      background: transparent;
      color: var(--text-muted);
      cursor: pointer;
      font-size: 13px;
      display: none;
      padding: 2px 6px;
      border-radius: 50%;
    }
    .tasks-search-wrap input:not(:placeholder-shown) + .search-clear {
      display: block;
    }

    .tasks-select-pill {
      background: var(--surface-gray);
      border: 1px solid transparent;
      border-radius: 10px;
      padding: 8px 12px;
      font: inherit;
      font-size: 13px;
      font-weight: 600;
      color: var(--text);
      outline: none;
      cursor: pointer;
      transition: all 0.15s ease;
    }
    .tasks-select-pill:focus {
      border-color: var(--primary);
      background: #FFFFFF;
    }

    .tasks-archive-toggle {
      border: 1px solid transparent;
      background: var(--surface-gray);
      color: var(--text-light);
      border-radius: 10px;
      padding: 8px 13px;
      font: inherit;
      font-size: 13px;
      font-weight: 600;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      transition: all 0.15s ease;
    }
    .tasks-archive-toggle:hover {
      background: #E8EAF0;
      color: var(--text);
    }
    .tasks-archive-toggle.active {
      background: #1E232D;
      color: #FFFFFF;
    }

    .btn-create-task {
      border: none;
      background: var(--primary);
      color: #FFFFFF;
      border-radius: 10px;
      padding: 8px 15px;
      font: inherit;
      font-size: 13px;
      font-weight: 700;
      cursor: pointer;
      display: inline-flex;
      align-items: center;
      gap: 7px;
      box-shadow: 0 1px 2px rgba(5, 116, 248, 0.2);
      transition: all 0.15s ease;
    }
    .btn-create-task:hover {
      opacity: 0.92;
      transform: translateY(-1px);
      box-shadow: 0 4px 12px rgba(5, 116, 248, 0.3);
    }

    /* 3. Канбан-доска */
    .tasks-board {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(260px, 1fr));
      gap: 14px;
      align-items: start;
    }
    .tasks-col {
      background: #F8F9FB;
      border-radius: 18px;
      padding: 12px;
      display: flex;
      flex-direction: column;
      gap: 10px;
      min-height: 320px;
      border: 1px solid #ECEEF3;
      transition: all 0.15s ease;
    }
    .tasks-col.drag-over {
      background: #EFF6FF;
      border-color: #60A5FA;
      box-shadow: 0 0 0 2px rgba(96, 165, 250, 0.25);
    }

    /* Шапка колонки со статусной пилюлей (Status Pill) */
    .tasks-col-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 2px 4px 6px;
    }
    .tasks-col-pill {
      display: inline-flex;
      align-items: center;
      gap: 7px;
      padding: 4px 10px 4px 8px;
      border-radius: 20px;
      font-size: 12.5px;
      font-weight: 700;
      letter-spacing: -0.1px;
    }
    .tasks-col-pill .col-emoji {
      font-size: 13px;
      line-height: 1;
    }
    .tasks-col-pill .col-count {
      font-size: 11.5px;
      font-weight: 800;
      background: rgba(255, 255, 255, 0.85);
      padding: 1px 6px;
      border-radius: 10px;
      margin-left: 2px;
      font-variant-numeric: tabular-nums;
    }
    .tasks-col-add-btn {
      border: none;
      background: transparent;
      color: var(--text-muted);
      cursor: pointer;
      border-radius: 8px;
      width: 26px;
      height: 26px;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 16px;
      font-weight: 700;
      transition: all 0.12s ease;
    }
    .tasks-col-add-btn:hover {
      background: #FFFFFF;
      color: var(--primary);
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.08);
    }

    .tasks-col-items {
      display: flex;
      flex-direction: column;
      gap: 10px;
      min-height: 140px;
      flex: 1;
    }
    .tasks-col-empty {
      text-align: center;
      color: var(--text-muted);
      font-size: 12.5px;
      padding: 34px 12px;
      border: 1.5px dashed #DCE0E8;
      border-radius: 14px;
      background: rgba(255, 255, 255, 0.4);
      pointer-events: none;
    }

    /* Кнопка быстрого добавления внизу колонки (как + New Page в Tasklify) */
    .tasks-col-quick-add {
      border: 1px dashed #D3D7E0;
      background: transparent;
      color: var(--text-muted);
      border-radius: 12px;
      padding: 8px 12px;
      font: inherit;
      font-size: 12.5px;
      font-weight: 600;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 6px;
      margin-top: 2px;
      transition: all 0.15s ease;
    }
    .tasks-col-quick-add:hover {
      background: #FFFFFF;
      border-color: #B0B7C3;
      color: var(--text);
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.04);
    }

    /* 4. Карточка задачи (Top-Tier Card) */
    .task-card {
      background: #FFFFFF;
      border-radius: 14px;
      padding: 14px;
      border: 1px solid #EAECEF;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.03), 0 1px 2px rgba(0, 0, 0, 0.02);
      display: flex;
      flex-direction: column;
      gap: 8px;
      cursor: grab;
      user-select: none;
      transition: transform 0.15s ease, box-shadow 0.15s ease, border-color 0.15s ease, opacity 0.15s ease;
      position: relative;
    }
    .task-card:hover {
      box-shadow: 0 6px 16px rgba(0, 0, 0, 0.06), 0 2px 4px rgba(0, 0, 0, 0.02);
      transform: translateY(-1.5px);
      border-color: #D3D7DF;
    }
    .task-card:active {
      cursor: grabbing;
    }
    .task-card.dragging {
      opacity: 0.45;
      transform: rotate(1.5deg) scale(0.98);
      box-shadow: 0 12px 28px rgba(0, 0, 0, 0.12);
    }

    /* Верхний ряд карточки: Бейджи (версия, приоритет) и стрелки */
    .task-card-top {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 6px;
    }
    .task-badges {
      display: flex;
      flex-wrap: wrap;
      align-items: center;
      gap: 5px;
    }
    .task-badge {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      padding: 2.5px 7.5px;
      border-radius: 6px;
      font-size: 11px;
      font-weight: 700;
      letter-spacing: -0.1px;
    }
    .task-badge.version {
      background: #EFF6FF;
      color: #2563EB;
      border: 1px solid #DBEAFE;
    }
    .task-badge.prio-high {
      background: #FEF2F2;
      color: #DC2626;
      border: 1px solid #FEE2E2;
    }
    .task-badge.prio-low {
      background: #F3F4F6;
      color: #6B7280;
      border: 1px solid #E5E7EB;
    }

    /* Стрелки быстрого сдвига статуса */
    .task-move-btns {
      display: flex;
      align-items: center;
      gap: 2px;
      opacity: 0.7;
      transition: opacity 0.12s;
    }
    .task-card:hover .task-move-btns {
      opacity: 1;
    }
    .task-btn-step {
      border: none;
      background: var(--surface-gray);
      color: var(--text-muted);
      border-radius: 6px;
      width: 22px;
      height: 22px;
      display: flex;
      align-items: center;
      justify-content: center;
      cursor: pointer;
      font-size: 11px;
      font-weight: 700;
      padding: 0;
      transition: all 0.12s ease;
    }
    .task-btn-step:hover:not(:disabled) {
      background: var(--primary);
      color: #FFFFFF;
    }
    .task-btn-step:disabled {
      opacity: 0.2;
      cursor: default;
    }

    /* Умная типографика задачи: Заголовок + Описание */
    .task-card-content {
      cursor: pointer;
    }
    .task-card-title {
      font-size: 13.5px;
      font-weight: 700;
      line-height: 1.4;
      color: #111827;
      word-break: break-word;
    }
    .task-card-body {
      font-size: 12.5px;
      line-height: 1.45;
      color: #6B7280;
      margin-top: 4px;
      word-break: break-word;
      white-space: pre-wrap;
    }
    .task-card-body.clamped {
      display: -webkit-box;
      -webkit-line-clamp: 4;
      -webkit-box-orient: vertical;
      overflow: hidden;
    }
    .task-text-toggle {
      font-size: 11.5px;
      color: var(--primary);
      cursor: pointer;
      font-weight: 600;
      margin-top: 3px;
      display: inline-block;
    }
    .task-text-toggle:hover {
      text-decoration: underline;
    }

    /* Встроенное превью картинок в карточке (как в Weihu) */
    .task-card-image-preview {
      margin-top: 4px;
      border-radius: 10px;
      overflow: hidden;
      border: 1px solid #EAECEF;
      max-height: 140px;
      cursor: pointer;
    }
    .task-card-image-preview img {
      width: 100%;
      height: 100%;
      max-height: 140px;
      object-fit: cover;
      display: block;
      transition: transform 0.2s ease;
    }
    .task-card-image-preview:hover img {
      transform: scale(1.03);
    }

    .task-attachments-chips {
      display: flex;
      flex-wrap: wrap;
      gap: 5px;
      margin-top: 2px;
    }
    .task-att-chip {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      background: var(--surface-gray);
      border: 1px solid #EAECEF;
      padding: 3px 7px;
      border-radius: 6px;
      font-size: 11px;
      font-weight: 600;
      color: var(--text-light);
      text-decoration: none;
      max-width: 140px;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
    .task-att-chip:hover {
      background: #E8EAF0;
      color: var(--text);
    }

    /* Нижний ряд карточки: Дата и действия */
    .task-card-foot {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-top: 4px;
      padding-top: 8px;
      border-top: 1px solid #F3F4F6;
      font-size: 11.5px;
      color: var(--text-muted);
    }
    .task-foot-left {
      display: flex;
      align-items: center;
      gap: 7px;
    }
    .task-date-badge {
      display: inline-flex;
      align-items: center;
      gap: 4px;
      font-size: 11px;
      font-weight: 600;
      color: #9CA3AF;
    }
    .task-foot-actions {
      display: flex;
      align-items: center;
      gap: 4px;
      opacity: 0.6;
      transition: opacity 0.12s ease;
    }
    .task-card:hover .task-foot-actions {
      opacity: 1;
    }
    .task-icon-action {
      border: none;
      background: transparent;
      color: var(--text-muted);
      cursor: pointer;
      padding: 4px;
      border-radius: 6px;
      display: flex;
      align-items: center;
      justify-content: center;
      transition: all 0.12s ease;
    }
    .task-icon-action:hover {
      background: var(--surface-gray);
      color: var(--text);
    }
    .task-icon-action.danger:hover {
      background: #FEE2E2;
      color: #DC2626;
    }

    /* 5. Компактный список */
    .tasks-list-wrap {
      background: var(--card-bg);
      border-radius: 16px;
      padding: 6px 14px;
      border: 1px solid #EAECEF;
      box-shadow: 0 1px 3px rgba(0, 0, 0, 0.02);
      overflow-x: auto;
    }
    .tasks-table {
      width: 100%;
      border-collapse: collapse;
      font-size: 13px;
    }
    .tasks-table th, .tasks-table td {
      padding: 12px 10px;
      text-align: left;
      border-bottom: 1px solid var(--surface-gray);
      vertical-align: middle;
    }
    .tasks-table th {
      color: var(--text-muted);
      font-size: 11.5px;
      font-weight: 700;
      text-transform: uppercase;
      letter-spacing: 0.4px;
    }
    .tasks-table tr:last-child td {
      border-bottom: none;
    }
    .tasks-table tr:hover td {
      background: #F9FAFB;
    }

    /* 6. Модальное окно создания и редактирования */
    .task-modal {
      border: none;
      border-radius: 20px;
      padding: 26px 28px;
      width: min(620px, 94vw);
      background: #FFFFFF;
      color: var(--text);
      box-shadow: 0 20px 50px rgba(0, 0, 0, 0.16);
      position: fixed;
      top: 50%;
      left: 50%;
      transform: translate(-50%, -50%);
      margin: 0;
    }
    .task-modal::backdrop {
      background: rgba(15, 23, 42, 0.5);
      backdrop-filter: blur(4px);
    }
    .task-modal-head {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-bottom: 20px;
    }
    .task-modal-title {
      font-size: 18px;
      font-weight: 800;
      margin: 0;
      letter-spacing: -0.3px;
    }
    .task-modal-close {
      border: none;
      background: var(--surface-gray);
      border-radius: 8px;
      width: 32px;
      height: 32px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      color: var(--text-muted);
      transition: all 0.12s;
    }
    .task-modal-close:hover {
      color: var(--text);
      background: #E5E7EB;
    }
    .task-form-group {
      margin-bottom: 16px;
    }
    .task-form-group label {
      display: block;
      font-size: 12px;
      font-weight: 700;
      color: var(--text-muted);
      margin-bottom: 6px;
      text-transform: uppercase;
      letter-spacing: 0.3px;
    }
    .task-textarea {
      width: 100%;
      box-sizing: border-box;
      min-height: 120px;
      max-height: 340px;
      border: 1px solid #D1D5DB;
      border-radius: 12px;
      padding: 12px 14px;
      font: inherit;
      font-size: 14px;
      line-height: 1.5;
      color: var(--text);
      resize: vertical;
      outline: none;
      transition: all 0.15s ease;
    }
    .task-textarea:focus {
      border-color: var(--primary);
      box-shadow: 0 0 0 3px var(--primary-subtle);
    }
    .task-form-row {
      display: grid;
      grid-template-columns: 1.2fr 1fr 1fr;
      gap: 12px;
      margin-bottom: 16px;
    }
    .task-form-input, .task-form-select {
      width: 100%;
      box-sizing: border-box;
      border: 1px solid #D1D5DB;
      border-radius: 10px;
      padding: 9px 11px;
      font: inherit;
      font-size: 13px;
      color: var(--text);
      outline: none;
      background: #FFFFFF;
      transition: all 0.15s;
    }
    .task-form-input:focus, .task-form-select:focus {
      border-color: var(--primary);
      box-shadow: 0 0 0 3px var(--primary-subtle);
    }

    .task-dropzone {
      border: 2px dashed #D1D5DB;
      border-radius: 12px;
      padding: 16px;
      text-align: center;
      background: #F9FAFB;
      cursor: pointer;
      transition: all 0.15s;
    }
    .task-dropzone.drag-active {
      border-color: var(--primary);
      background: #EFF6FF;
    }
    .task-dropzone-text {
      font-size: 12.5px;
      color: var(--text-light);
      margin-top: 4px;
    }
    .task-dropzone-kbd {
      display: inline-block;
      padding: 2px 6px;
      background: #E5E7EB;
      border-radius: 5px;
      font-size: 11px;
      font-weight: 700;
      color: var(--text);
    }
    .task-modal-attachments {
      display: flex;
      flex-wrap: wrap;
      gap: 8px;
      margin-top: 10px;
    }
    .task-modal-att-item {
      display: inline-flex;
      align-items: center;
      gap: 6px;
      background: var(--surface-gray);
      border: 1px solid #E5E7EB;
      border-radius: 8px;
      padding: 4px 8px;
      font-size: 12px;
    }
    .task-modal-att-remove {
      border: none;
      background: transparent;
      color: var(--text-muted);
      cursor: pointer;
      padding: 0 2px;
      font-size: 14px;
    }
    .task-modal-att-remove:hover {
      color: #DC2626;
    }

    .task-modal-foot {
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin-top: 22px;
      padding-top: 16px;
      border-top: 1px solid #F3F4F6;
    }
    .task-modal-actions {
      display: flex;
      align-items: center;
      gap: 10px;
      margin-left: auto;
    }

    /* Лайтбокс картинок */
    .task-lightbox {
      border: none;
      background: transparent;
      padding: 0;
      max-width: 90vw;
      max-height: 90vh;
      margin: auto;
      outline: none;
    }
    .task-lightbox::backdrop {
      background: rgba(0, 0, 0, 0.85);
      backdrop-filter: blur(5px);
    }
    .task-lightbox img {
      max-width: 90vw;
      max-height: 85vh;
      border-radius: 14px;
      box-shadow: 0 12px 40px rgba(0, 0, 0, 0.5);
      display: block;
    }

    @media (max-width: 900px) {
      .tasks-kpi-grid { grid-template-columns: repeat(2, 1fr); }
    }
    @media (max-width: 600px) {
      .tasks-kpi-grid { grid-template-columns: 1fr; }
      .tasks-form-row { grid-template-columns: 1fr; }
    }
  </style>

  <div class="tasks-wrap">
    <!-- 1. Карточки метрик (Task KPI Cards) -->
    <div class="tasks-kpi-grid">
      <div class="tasks-kpi-card" data-kpi-status="all" title="Показать все задачи">
        <div class="tasks-kpi-head">
          <span class="tasks-kpi-label">Всего задач</span>
          <span class="tasks-kpi-icon" style="background:#F3F4F6; color:#4B5563;">📋</span>
        </div>
        <div class="tasks-kpi-value" id="tasks-kpi-total">0</div>
        <div class="tasks-kpi-sub">В текущем бэклоге</div>
      </div>

      <div class="tasks-kpi-card" data-kpi-status="in_progress" title="Отфильтровать задачи в работе">
        <div class="tasks-kpi-head">
          <span class="tasks-kpi-label">В работе сейчас</span>
          <span class="tasks-kpi-icon" style="background:#EDE9FE; color:#7C3AED;">⚡</span>
        </div>
        <div class="tasks-kpi-value" id="tasks-kpi-progress" style="color:#7C3AED;">0</div>
        <div class="tasks-kpi-sub">В разработке прямо сейчас</div>
      </div>

      <div class="tasks-kpi-card" data-kpi-status="ready" title="Отфильтровать готовые к релизу">
        <div class="tasks-kpi-head">
          <span class="tasks-kpi-label">Ждёт релиза</span>
          <span class="tasks-kpi-icon" style="background:#D1FAE5; color:#059669;">🧪</span>
        </div>
        <div class="tasks-kpi-value" id="tasks-kpi-ready" style="color:#059669;">0</div>
        <div class="tasks-kpi-sub">Готово в коде, не выложено</div>
      </div>

      <div class="tasks-kpi-card" data-kpi-status="released" title="Отфильтровать выпущенные в сторах">
        <div class="tasks-kpi-head">
          <span class="tasks-kpi-label">Выпущено в сторах</span>
          <span class="tasks-kpi-icon" style="background:#DCFCE7; color:#16A34A;">🚀</span>
        </div>
        <div class="tasks-kpi-value" id="tasks-kpi-released" style="color:#16A34A;">0</div>
        <div class="tasks-kpi-sub">Доступно пользователям</div>
      </div>
    </div>

    <!-- 2. Верхняя панель: поиск, фильтры, переключатель вида, кнопка добавления -->
    <div class="tasks-toolbar">
      <div class="tasks-toolbar-left">
        <div class="tasks-segmented" id="tasks-view-toggle">
          <button class="active" data-view="board" title="Канбан-доска">
            <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="18" rx="1"/><rect x="14" y="3" width="7" height="11" rx="1"/></svg>
            <span>Доска</span>
          </button>
          <button data-view="list" title="Табличный список">
            <svg viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2"><line x1="8" y1="6" x2="21" y2="6"/><line x1="8" y1="12" x2="21" y2="12"/><line x1="8" y1="18" x2="21" y2="18"/><line x1="3" y1="6" x2="3.01" y2="6"/><line x1="3" y1="12" x2="3.01" y2="12"/><line x1="3" y1="18" x2="3.01" y2="18"/></svg>
            <span>Список</span>
          </button>
        </div>

        <div class="tasks-search-wrap">
          <svg class="search-icon" viewBox="0 0 24 24" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2"><circle cx="11" cy="11" r="8"/><line x1="21" y1="21" x2="16.65" y2="16.65"/></svg>
          <input type="search" id="tasks-search-input" placeholder="Поиск по задачам…" aria-label="Поиск по задачам">
          <button class="search-clear" id="tasks-search-clear" type="button" title="Очистить поиск">✕</button>
        </div>

        <select class="tasks-select-pill" id="tasks-version-filter" title="Фильтр по версии игры">
          <option value="all">Все версии</option>
          <option value="none">Без версии</option>
        </select>

        <select class="tasks-select-pill" id="tasks-priority-filter" title="Фильтр по приоритету">
          <option value="all">Все приоритеты</option>
          <option value="high">🔥 Высокий</option>
          <option value="normal">⚡ Обычный</option>
          <option value="low">💤 Низкий</option>
        </select>
      </div>

      <div class="tasks-toolbar-right">
        <button class="tasks-archive-toggle" id="tasks-archive-btn" title="Показать или скрыть архивные задачи">
          <span>📦 Архив</span>
          <span id="tasks-archive-count" style="font-size:11.5px; opacity:.85; font-variant-numeric:tabular-nums;">(0)</span>
        </button>
        <button class="btn-create-task" id="tasks-add-task-btn">
          <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
          <span>Новая задача</span>
        </button>
      </div>
    </div>

    <!-- 3. Канбан-доска -->
    <div class="tasks-board" id="tasks-board-container">
      <!-- Колонки генерируются динамически -->
    </div>

    <!-- 4. Компактный список (по умолчанию скрыт) -->
    <div class="tasks-list-wrap" id="tasks-list-container" style="display:none">
      <table class="tasks-table">
        <thead>
          <tr>
            <th style="width:140px">Статус</th>
            <th>Задача</th>
            <th style="width:110px">Версия</th>
            <th style="width:110px">Приоритет</th>
            <th style="width:90px">Файлы</th>
            <th style="width:110px">Дата</th>
            <th style="width:100px; text-align:right">Действия</th>
          </tr>
        </thead>
        <tbody id="tasks-table-body">
          <tr><td colspan="7" style="text-align:center; color:var(--text-muted); padding:30px;">Загрузка…</td></tr>
        </tbody>
      </table>
    </div>
  </div>

  <!-- Модальное окно создания и редактирования задачи -->
  <dialog class="task-modal" id="tasks-edit-modal">
    <div class="task-modal-head">
      <h3 class="task-modal-title" id="tasks-modal-heading">Новая задача</h3>
      <button class="task-modal-close" id="tasks-modal-close-btn" type="button" aria-label="Закрыть">✕</button>
    </div>

    <form id="tasks-edit-form">
      <input type="hidden" id="task-form-id" value="">

      <div class="task-form-group">
        <label for="task-form-text">Описание идеи или задачи</label>
        <textarea class="task-textarea" id="task-form-text" placeholder="Опишите идею, план, баг или доработку для приложения/игры… Первая строка станет заголовком задачи, последующие — описанием." required autofocus></textarea>
      </div>

      <div class="task-form-row">
        <div class="task-form-group" style="margin:0">
          <label for="task-form-status">Статус</label>
          <select class="task-form-select" id="task-form-status">
            <option value="idea">💡 Идея</option>
            <option value="planned">📋 В планах</option>
            <option value="in_progress">⚡ В работе</option>
            <option value="ready">🧪 Готово (ждёт релиза)</option>
            <option value="released">🚀 Выпущено в сторах</option>
            <option value="archived">📦 Архив</option>
          </select>
        </div>

        <div class="task-form-group" style="margin:0">
          <label for="task-form-version">Версия игры / аппа</label>
          <input class="task-form-input" id="task-form-version" list="tasks-versions-datalist" placeholder="Например: v1.0.7">
          <datalist id="tasks-versions-datalist"></datalist>
        </div>

        <div class="task-form-group" style="margin:0">
          <label for="task-form-priority">Приоритет</label>
          <select class="task-form-select" id="task-form-priority">
            <option value="high">🔥 Высокий (Срочно)</option>
            <option value="normal" selected>⚡ Обычный</option>
            <option value="low">💤 Низкий</option>
          </select>
        </div>
      </div>

      <div class="task-form-group">
        <label>Прикрепление скриншотов и файлов</label>
        <div class="task-dropzone" id="task-file-dropzone">
          <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2" style="color:var(--text-muted);"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="17 8 12 3 7 8"/><line x1="12" y1="3" x2="12" y2="15"/></svg>
          <div class="task-dropzone-text">
            Перетащите файлы сюда, кликните для выбора или нажмите <span class="task-dropzone-kbd">Cmd+V</span> для вставки скриншота из буфера
          </div>
          <input type="file" id="task-file-input" multiple style="display:none">
        </div>
        <div class="task-modal-attachments" id="task-form-attachments-list"></div>
      </div>

      <div class="task-modal-foot">
        <button class="btn-action" id="task-form-delete-btn" type="button" style="color:#DC2626; border-color:#FEE2E2; display:none;">Удалить навсегда</button>
        <div class="task-modal-actions">
          <button class="btn-action" id="task-form-cancel-btn" type="button">Отмена</button>
          <button class="btn-action primary" id="task-form-save-btn" type="submit">Сохранить</button>
        </div>
      </div>
    </form>
  </dialog>

  <!-- Лайтбокс для просмотра картинок во весь экран -->
  <dialog class="task-lightbox" id="tasks-image-lightbox">
    <img id="tasks-lightbox-img" src="" alt="Скриншот задачи">
  </dialog>
</div>
`;

export const TASKS_CLIENT_JS = `
VIEW_TITLES.tasks = 'Задачи';

(function() {
  var STATUS_DEFS = [
    { id: 'idea', name: 'Идея', emoji: '💡', bg: '#FEF3C7', color: '#B45309' },
    { id: 'planned', name: 'В планах', emoji: '📋', bg: '#E0F2FE', color: '#0369A1' },
    { id: 'in_progress', name: 'В работе', emoji: '⚡', bg: '#EDE9FE', color: '#6D28D9' },
    { id: 'ready', name: 'Готово (ждёт релиза)', emoji: '🧪', bg: '#D1FAE5', color: '#047857' },
    { id: 'released', name: 'Выпущено в сторах', emoji: '🚀', bg: '#DCFCE7', color: '#15803D' },
    { id: 'archived', name: 'Архив', emoji: '📦', bg: '#F1F5F9', color: '#475569' }
  ];

  var allTasks = [];
  var currentVersions = [];
  var showArchive = false;
  var currentView = 'board';
  var searchQuery = '';
  var versionFilter = 'all';
  var priorityFilter = 'all';
  var statusFilter = 'all';
  var modalPendingAttachments = [];
  var draggedTaskId = null;
  var isLoaded = false;

  var boardEl = document.getElementById('tasks-board-container');
  var listWrapEl = document.getElementById('tasks-list-container');
  var tableBodyEl = document.getElementById('tasks-table-body');
  var searchInput = document.getElementById('tasks-search-input');
  var searchClearBtn = document.getElementById('tasks-search-clear');
  var versionSelect = document.getElementById('tasks-version-filter');
  var prioritySelect = document.getElementById('tasks-priority-filter');
  var archiveBtn = document.getElementById('tasks-archive-btn');
  var archiveCountEl = document.getElementById('tasks-archive-count');
  var viewToggle = document.getElementById('tasks-view-toggle');
  var addBtn = document.getElementById('tasks-add-task-btn');

  var kpiTotalEl = document.getElementById('tasks-kpi-total');
  var kpiProgressEl = document.getElementById('tasks-kpi-progress');
  var kpiReadyEl = document.getElementById('tasks-kpi-ready');
  var kpiReleasedEl = document.getElementById('tasks-kpi-released');

  var modal = document.getElementById('tasks-edit-modal');
  var form = document.getElementById('tasks-edit-form');
  var modalHeading = document.getElementById('tasks-modal-heading');
  var formIdInput = document.getElementById('task-form-id');
  var formTextInput = document.getElementById('task-form-text');
  var formStatusSelect = document.getElementById('task-form-status');
  var formVersionInput = document.getElementById('task-form-version');
  var formPrioritySelect = document.getElementById('task-form-priority');
  var formDeleteBtn = document.getElementById('task-form-delete-btn');
  var formCancelBtn = document.getElementById('task-form-cancel-btn');
  var modalCloseBtn = document.getElementById('tasks-modal-close-btn');
  var dropzone = document.getElementById('task-file-dropzone');
  var fileInput = document.getElementById('task-file-input');
  var formAttList = document.getElementById('task-form-attachments-list');
  var lightbox = document.getElementById('tasks-image-lightbox');
  var lightboxImg = document.getElementById('tasks-lightbox-img');

  function notify(msg, isErr) {
    if (typeof adminToast === 'function') adminToast(msg, isErr);
    else if (typeof scToast === 'function') scToast(msg, isErr);
    else if (isErr) alert(msg);
  }

  function esc(s) {
    return typeof adminEsc === 'function' ? adminEsc(s) : String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
  }

  function formatDate(ts) {
    if (!ts) return '';
    var d = new Date(ts);
    var now = new Date();
    var isToday = d.toDateString() === now.toDateString();
    if (isToday) return 'Сегодня';
    var yesterday = new Date(now.getTime() - 86400000);
    if (d.toDateString() === yesterday.toDateString()) return 'Вчера';
    return d.toLocaleDateString('ru-RU', { day: 'numeric', month: 'short' });
  }

  function splitTaskText(raw) {
    if (!raw) return { title: 'Без названия', body: '' };
    var text = String(raw).trim();
    var newlineIdx = text.indexOf('\\n');
    if (newlineIdx !== -1) {
      return {
        title: text.slice(0, newlineIdx).trim(),
        body: text.slice(newlineIdx + 1).trim()
      };
    }
    var dotIdx = text.indexOf('. ');
    if (dotIdx !== -1 && dotIdx <= 110) {
      return {
        title: text.slice(0, dotIdx + 1).trim(),
        body: text.slice(dotIdx + 2).trim()
      };
    }
    if (text.length <= 80) {
      return { title: text, body: '' };
    }
    var spaceIdx = text.indexOf(' ', 70);
    if (spaceIdx !== -1 && spaceIdx <= 100) {
      return {
        title: text.slice(0, spaceIdx).trim() + '…',
        body: text.slice(spaceIdx + 1).trim()
      };
    }
    return { title: text, body: '' };
  }

  async function api(path, method, body) {
    var opts = { method: method || 'GET', headers: {} };
    if (body) {
      opts.headers['content-type'] = 'application/json';
      opts.body = JSON.stringify(body);
    }
    var res = await fetch('/api/admin/tasks' + path, opts);
    var data = await res.json().catch(function() { return {}; });
    if (!res.ok) throw new Error(data.error || ('Ошибка сервера ' + res.status));
    return data;
  }

  async function loadTasks() {
    try {
      var res = await api('', 'GET');
      allTasks = res.tasks || [];
      currentVersions = res.versions || [];
      isLoaded = true;
      syncVersionsDropdown();
      render();
    } catch (err) {
      notify('Не удалось загрузить задачи: ' + err.message, true);
    }
  }

  function syncVersionsDropdown() {
    var cur = versionSelect.value;
    var html = '<option value="all">Все версии</option><option value="none">Без версии</option>';
    currentVersions.forEach(function(v) {
      html += '<option value="' + esc(v) + '">' + esc(v) + '</option>';
    });
    versionSelect.innerHTML = html;
    if (cur && (cur === 'all' || cur === 'none' || currentVersions.indexOf(cur) !== -1)) {
      versionSelect.value = cur;
    }

    var datalist = document.getElementById('tasks-versions-datalist');
    if (datalist) {
      datalist.innerHTML = currentVersions.map(function(v) {
        return '<option value="' + esc(v) + '">';
      }).join('');
    }
  }

  function updateKpiCards() {
    var total = allTasks.filter(function(t) { return t.status !== 'archived'; }).length;
    var inProgress = allTasks.filter(function(t) { return t.status === 'in_progress'; }).length;
    var ready = allTasks.filter(function(t) { return t.status === 'ready'; }).length;
    var released = allTasks.filter(function(t) { return t.status === 'released'; }).length;

    if (kpiTotalEl) kpiTotalEl.textContent = total;
    if (kpiProgressEl) kpiProgressEl.textContent = inProgress;
    if (kpiReadyEl) kpiReadyEl.textContent = ready;
    if (kpiReleasedEl) kpiReleasedEl.textContent = released;

    document.querySelectorAll('.tasks-kpi-card').forEach(function(card) {
      card.classList.toggle('active', card.dataset.kpiStatus === statusFilter);
    });
  }

  function getFilteredTasks() {
    var q = searchQuery.trim().toLowerCase();
    return allTasks.filter(function(t) {
      if (q && (t.text || '').toLowerCase().indexOf(q) === -1 && (t.version || '').toLowerCase().indexOf(q) === -1) {
        return false;
      }
      if (versionFilter === 'none' && t.version) return false;
      if (versionFilter !== 'all' && versionFilter !== 'none' && t.version !== versionFilter) return false;
      if (priorityFilter !== 'all' && (t.priority || 'normal') !== priorityFilter) return false;
      if (statusFilter !== 'all' && t.status !== statusFilter) return false;
      return true;
    });
  }

  function render() {
    updateKpiCards();
    var filtered = getFilteredTasks();
    var archivedCount = allTasks.filter(function(t) { return t.status === 'archived'; }).length;
    if (archiveCountEl) archiveCountEl.textContent = '(' + archivedCount + ')';

    if (currentView === 'board') {
      boardEl.style.display = 'grid';
      listWrapEl.style.display = 'none';
      renderBoard(filtered);
    } else {
      boardEl.style.display = 'none';
      listWrapEl.style.display = 'block';
      renderList(filtered);
    }
  }

  function renderBoard(filtered) {
    var activeStatuses = STATUS_DEFS.filter(function(s) {
      if (statusFilter !== 'all' && s.id !== statusFilter) return false;
      return s.id !== 'archived' || showArchive;
    });

    var html = activeStatuses.map(function(colDef) {
      var colTasks = filtered.filter(function(t) { return (t.status || 'idea') === colDef.id; });
      var itemsHtml = colTasks.length === 0
        ? '<div class="tasks-col-empty">Нет задач в этой колонке</div>'
        : colTasks.map(function(t) { return renderCard(t); }).join('');

      return '<div class="tasks-col" data-col-status="' + colDef.id + '">' +
        '<div class="tasks-col-head">' +
          '<div class="tasks-col-pill" style="background:' + colDef.bg + '; color:' + colDef.color + ';">' +
            '<span class="col-emoji">' + colDef.emoji + '</span>' +
            '<span>' + esc(colDef.name) + '</span>' +
            '<span class="col-count">' + colTasks.length + '</span>' +
          '</div>' +
          '<button class="tasks-col-add-btn" data-add-to-status="' + colDef.id + '" title="Добавить задачу сюда">+</button>' +
        '</div>' +
        '<div class="tasks-col-items" data-col-status="' + colDef.id + '">' + itemsHtml + '</div>' +
        '<button class="tasks-col-quick-add" data-add-to-status="' + colDef.id + '">+ Добавить задачу</button>' +
      '</div>';
    }).join('');

    boardEl.innerHTML = html;
    bindCardEvents();
  }

  function renderCard(t) {
    var statusIdx = STATUS_DEFS.findIndex(function(s) { return s.id === (t.status || 'idea'); });
    var canMoveLeft = statusIdx > 0;
    var canMoveRight = statusIdx < STATUS_DEFS.length - 2; // перед архивом

    var badgesHtml = '';
    if (t.version) {
      badgesHtml += '<span class="task-badge version" title="Версия">🏷️ ' + esc(t.version) + '</span>';
    }
    if (t.priority === 'high') {
      badgesHtml += '<span class="task-badge prio-high">🔥 Срочно</span>';
    } else if (t.priority === 'low') {
      badgesHtml += '<span class="task-badge prio-low">💤 Низкий</span>';
    }

    var imagePreviewHtml = '';
    var otherAttsHtml = '';
    if (Array.isArray(t.attachments) && t.attachments.length) {
      var firstImg = t.attachments.find(function(a) { return a.type && a.type.startsWith('image/'); });
      if (firstImg) {
        var imgUrl = '/api/admin/tasks/attachment/' + encodeURIComponent(firstImg.id);
        imagePreviewHtml = '<div class="task-card-image-preview" data-lightbox-src="' + imgUrl + '">' +
          '<img src="' + imgUrl + '" alt="' + esc(firstImg.name) + '" loading="lazy">' +
        '</div>';
      }

      var nonImgOrExtra = t.attachments.filter(function(a) { return a !== firstImg; });
      if (nonImgOrExtra.length) {
        otherAttsHtml = '<div class="task-attachments-chips">' + nonImgOrExtra.map(function(a) {
          var url = '/api/admin/tasks/attachment/' + encodeURIComponent(a.id);
          var isImg = a.type && a.type.startsWith('image/');
          if (isImg) {
            return '<span class="task-att-chip" data-lightbox-src="' + url + '" style="cursor:pointer;">🖼️ ' + esc(a.name) + '</span>';
          }
          return '<a class="task-att-chip" href="' + url + '" target="_blank" download="' + esc(a.name) + '" title="' + esc(a.name) + '">📎 ' + esc(a.name) + '</a>';
        }).join('') + '</div>';
      }
    }

    var parts = splitTaskText(t.text);
    var hasBody = Boolean(parts.body);
    var isLong = parts.body.length > 180 || (parts.body.match(/\\n/g) || []).length > 3;

    return '<div class="task-card" draggable="true" data-task-id="' + t.id + '">' +
      '<div class="task-card-top">' +
        '<div class="task-badges">' + badgesHtml + '</div>' +
        '<div class="task-move-btns">' +
          '<button class="task-btn-step" data-move-task="' + t.id + '" data-dir="prev" ' + (canMoveLeft ? '' : 'disabled') + ' title="Предыдущий статус">←</button>' +
          '<button class="task-btn-step" data-move-task="' + t.id + '" data-dir="next" ' + (canMoveRight ? '' : 'disabled') + ' title="Следующий статус">→</button>' +
        '</div>' +
      '</div>' +
      imagePreviewHtml +
      '<div class="task-card-content" data-edit-task="' + t.id + '">' +
        '<div class="task-card-title">' + esc(parts.title) + '</div>' +
        (hasBody ? '<div class="task-card-body ' + (isLong ? 'clamped' : '') + '">' + esc(parts.body) + '</div>' : '') +
      '</div>' +
      (hasBody && isLong ? '<div class="task-text-toggle" data-toggle-text>Развернуть ↓</div>' : '') +
      otherAttsHtml +
      '<div class="task-card-foot">' +
        '<div class="task-foot-left">' +
          '<span class="task-date-badge">' +
            '<svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 16 14"/></svg>' +
            formatDate(t.updatedAt || t.createdAt) +
          '</span>' +
          (Array.isArray(t.attachments) && t.attachments.length ? '<span style="font-size:11px; color:#9CA3AF;">📎 ' + t.attachments.length + '</span>' : '') +
        '</div>' +
        '<div class="task-foot-actions">' +
          '<button class="task-icon-action" data-edit-task="' + t.id + '" title="Редактировать">' +
            '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>' +
          '</button>' +
          '<button class="task-icon-action danger" data-delete-task="' + t.id + '" title="Удалить навсегда">' +
            '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>' +
          '</button>' +
        '</div>' +
      '</div>' +
    '</div>';
  }

  function renderList(filtered) {
    if (!filtered.length) {
      tableBodyEl.innerHTML = '<tr><td colspan="7" style="text-align:center; color:var(--text-muted); padding:30px;">Задачи не найдены</td></tr>';
      return;
    }

    var html = filtered.map(function(t) {
      var statusDef = STATUS_DEFS.find(function(s) { return s.id === (t.status || 'idea'); }) || STATUS_DEFS[0];
      var prioLabel = t.priority === 'high' ? '🔥 Высокий' : t.priority === 'low' ? '💤 Низкий' : '⚡ Обычный';
      var filesCount = Array.isArray(t.attachments) ? t.attachments.length : 0;
      var parts = splitTaskText(t.text);

      return '<tr data-task-id="' + t.id + '">' +
        '<td><span class="tasks-col-pill" style="background:' + statusDef.bg + '; color:' + statusDef.color + '; font-size:11.5px; padding:3px 8px;">' + statusDef.emoji + ' ' + esc(statusDef.name) + '</span></td>' +
        '<td>' +
          '<div style="font-weight:700; color:#111827; cursor:pointer;" data-edit-task="' + t.id + '">' + esc(parts.title) + '</div>' +
          (parts.body ? '<div style="font-size:12px; color:#6B7280; margin-top:2px; max-width:500px; white-space:nowrap; overflow:hidden; text-overflow:ellipsis;">' + esc(parts.body) + '</div>' : '') +
        '</td>' +
        '<td>' + (t.version ? '<span class="task-badge version">🏷️ ' + esc(t.version) + '</span>' : '—') + '</td>' +
        '<td>' + prioLabel + '</td>' +
        '<td>' + (filesCount ? '📎 ' + filesCount : '—') + '</td>' +
        '<td><small style="color:#9CA3AF; font-weight:600;">' + formatDate(t.updatedAt || t.createdAt) + '</small></td>' +
        '<td style="text-align:right">' +
          '<button class="task-icon-action" data-edit-task="' + t.id + '" style="display:inline-flex;" title="Редактировать">' +
            '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>' +
          '</button>' +
          '<button class="task-icon-action danger" data-delete-task="' + t.id + '" style="display:inline-flex; margin-left:4px;" title="Удалить">' +
            '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>' +
          '</button>' +
        '</td>' +
      '</tr>';
    }).join('');

    tableBodyEl.innerHTML = html;
    bindCardEvents();
  }

  function bindCardEvents() {
    document.querySelectorAll('.task-card').forEach(function(card) {
      card.addEventListener('dragstart', function(e) {
        draggedTaskId = card.dataset.taskId;
        card.classList.add('dragging');
        e.dataTransfer.setData('text/plain', draggedTaskId);
        e.dataTransfer.effectAllowed = 'move';
      });
      card.addEventListener('dragend', function() {
        card.classList.remove('dragging');
        draggedTaskId = null;
        document.querySelectorAll('.tasks-col').forEach(function(col) { col.classList.remove('drag-over'); });
      });
    });

    document.querySelectorAll('.tasks-col').forEach(function(col) {
      col.addEventListener('dragover', function(e) {
        e.preventDefault();
        e.dataTransfer.dropEffect = 'move';
        col.classList.add('drag-over');
      });
      col.addEventListener('dragleave', function() {
        col.classList.remove('drag-over');
      });
      col.addEventListener('drop', async function(e) {
        e.preventDefault();
        col.classList.remove('drag-over');
        var targetStatus = col.dataset.colStatus;
        var taskId = e.dataTransfer.getData('text/plain') || draggedTaskId;
        if (!taskId || !targetStatus) return;

        var task = allTasks.find(function(t) { return t.id === taskId; });
        if (!task || task.status === targetStatus) return;

        task.status = targetStatus;
        render();

        try {
          await api('/move', 'POST', { id: taskId, status: targetStatus });
        } catch (err) {
          notify('Не удалось переместить задачу: ' + err.message, true);
          loadTasks();
        }
      });
    });
  }

  // Делегированные клики
  var container = document.getElementById('tasks-view');
  container.addEventListener('click', async function(e) {
    // KPI карточки
    var kpiCard = e.target.closest('[data-kpi-status]');
    if (kpiCard) {
      var targetKpi = kpiCard.dataset.kpiStatus;
      statusFilter = statusFilter === targetKpi ? 'all' : targetKpi;
      render();
      return;
    }

    // Добавить в статус
    var colAddBtn = e.target.closest('[data-add-to-status]');
    if (colAddBtn) {
      openModal(null, colAddBtn.dataset.addToStatus);
      return;
    }

    // Шаг стрелками
    var stepBtn = e.target.closest('[data-move-task]');
    if (stepBtn) {
      var taskId = stepBtn.dataset.moveTask;
      var dir = stepBtn.dataset.dir;
      var task = allTasks.find(function(t) { return t.id === taskId; });
      if (!task) return;

      var curIdx = STATUS_DEFS.findIndex(function(s) { return s.id === (task.status || 'idea'); });
      var nextIdx = dir === 'next' ? curIdx + 1 : curIdx - 1;
      if (nextIdx >= 0 && nextIdx < STATUS_DEFS.length) {
        var nextStatus = STATUS_DEFS[nextIdx].id;
        task.status = nextStatus;
        render();
        try {
          await api('/move', 'POST', { id: taskId, status: nextStatus });
        } catch (err) {
          notify('Не удалось обновить статус: ' + err.message, true);
          loadTasks();
        }
      }
      return;
    }

    // Редактировать задачу
    var editTarget = e.target.closest('[data-edit-task]');
    if (editTarget) {
      openModal(editTarget.dataset.editTask);
      return;
    }

    // Удалить задачу
    var deleteBtn = e.target.closest('[data-delete-task]');
    if (deleteBtn) {
      var idToDelete = deleteBtn.dataset.deleteTask;
      if (!confirm('Вы действительно хотите навсегда удалить эту задачу?')) return;
      try {
        await api('/delete', 'POST', { id: idToDelete });
        allTasks = allTasks.filter(function(t) { return t.id !== idToDelete; });
        render();
        notify('Задача удалена');
      } catch (err) {
        notify('Ошибка удаления: ' + err.message, true);
      }
      return;
    }

    // Развернуть/свернуть текст
    var textToggle = e.target.closest('[data-toggle-text]');
    if (textToggle) {
      var cardContent = textToggle.previousElementSibling;
      var bodyEl = cardContent ? cardContent.querySelector('.task-card-body') : null;
      if (bodyEl) {
        bodyEl.classList.toggle('clamped');
        textToggle.textContent = bodyEl.classList.contains('clamped') ? 'Развернуть ↓' : 'Свернуть ↑';
      }
      return;
    }

    // Просмотр картинки в лайтбоксе
    var imgThumb = e.target.closest('[data-lightbox-src]');
    if (imgThumb) {
      lightboxImg.src = imgThumb.dataset.lightboxSrc;
      lightbox.showModal();
      return;
    }
  });

  lightbox.addEventListener('click', function() { lightbox.close(); });

  // Переключение вида (Доска / Список)
  viewToggle.addEventListener('click', function(e) {
    var btn = e.target.closest('button');
    if (!btn || !btn.dataset.view) return;
    viewToggle.querySelectorAll('button').forEach(function(b) { b.classList.remove('active'); });
    btn.classList.add('active');
    currentView = btn.dataset.view;
    render();
  });

  // Поиск и фильтры
  searchInput.addEventListener('input', function() {
    searchQuery = searchInput.value;
    render();
  });
  if (searchClearBtn) {
    searchClearBtn.addEventListener('click', function() {
      searchInput.value = '';
      searchQuery = '';
      render();
      searchInput.focus();
    });
  }
  versionSelect.addEventListener('change', function() {
    versionFilter = versionSelect.value;
    render();
  });
  prioritySelect.addEventListener('change', function() {
    priorityFilter = prioritySelect.value;
    render();
  });
  archiveBtn.addEventListener('click', function() {
    showArchive = !showArchive;
    archiveBtn.classList.toggle('active', showArchive);
    render();
  });

  // Кнопка добавления задачи
  addBtn.addEventListener('click', function() {
    openModal(null, 'idea');
  });

  // Модальное окно
  function openModal(taskId, defaultStatus) {
    var task = taskId ? allTasks.find(function(t) { return t.id === taskId; }) : null;
    modalHeading.textContent = task ? 'Редактирование задачи' : 'Новая задача';
    formIdInput.value = task ? task.id : '';
    formTextInput.value = task ? (task.text || '') : '';
    formStatusSelect.value = task ? (task.status || 'idea') : (defaultStatus || 'idea');
    formVersionInput.value = task ? (task.version || '') : (versionFilter !== 'all' && versionFilter !== 'none' ? versionFilter : '');
    formPrioritySelect.value = task ? (task.priority || 'normal') : 'normal';
    formDeleteBtn.style.display = task ? 'inline-block' : 'none';

    modalPendingAttachments = task && Array.isArray(task.attachments) ? task.attachments.slice() : [];
    renderModalAttachments();

    modal.showModal();
    formTextInput.focus();
  }

  function renderModalAttachments() {
    formAttList.innerHTML = modalPendingAttachments.map(function(a, idx) {
      return '<span class="task-modal-att-item">' +
        '<span>📎 ' + esc(a.name) + '</span>' +
        '<button class="task-modal-att-remove" type="button" data-att-idx="' + idx + '">✕</button>' +
      '</span>';
    }).join('');
  }

  formAttList.addEventListener('click', function(e) {
    var removeBtn = e.target.closest('[data-att-idx]');
    if (removeBtn) {
      var idx = parseInt(removeBtn.dataset.attIdx, 10);
      modalPendingAttachments.splice(idx, 1);
      renderModalAttachments();
    }
  });

  function closeModal() {
    modal.close();
  }
  modalCloseBtn.addEventListener('click', closeModal);
  formCancelBtn.addEventListener('click', closeModal);

  formDeleteBtn.addEventListener('click', async function() {
    var id = formIdInput.value;
    if (!id || !confirm('Удалить эту задачу навсегда?')) return;
    try {
      await api('/delete', 'POST', { id: id });
      allTasks = allTasks.filter(function(t) { return t.id !== id; });
      closeModal();
      render();
      notify('Задача удалена');
    } catch (err) {
      notify('Ошибка удаления: ' + err.message, true);
    }
  });

  form.addEventListener('submit', async function(e) {
    e.preventDefault();
    var text = formTextInput.value.trim();
    if (!text) return;

    var payload = {
      id: formIdInput.value || undefined,
      text: text,
      status: formStatusSelect.value,
      version: formVersionInput.value.trim(),
      priority: formPrioritySelect.value,
      attachments: modalPendingAttachments
    };

    var saveBtn = document.getElementById('task-form-save-btn');
    saveBtn.disabled = true;
    saveBtn.textContent = 'Сохранение…';

    try {
      var res = await api('/save', 'POST', payload);
      var saved = res.task;
      var existingIdx = allTasks.findIndex(function(t) { return t.id === saved.id; });
      if (existingIdx !== -1) {
        allTasks[existingIdx] = saved;
      } else {
        allTasks.unshift(saved);
      }
      currentVersions = res.versions || currentVersions;
      syncVersionsDropdown();
      closeModal();
      render();
      notify('Задача сохранена');
    } catch (err) {
      notify('Ошибка сохранения: ' + err.message, true);
    } finally {
      saveBtn.disabled = false;
      saveBtn.textContent = 'Сохранить';
    }
  });

  // Загрузка файлов
  dropzone.addEventListener('click', function() { fileInput.click(); });
  fileInput.addEventListener('change', function() {
    handleFiles(fileInput.files);
    fileInput.value = '';
  });

  dropzone.addEventListener('dragover', function(e) {
    e.preventDefault();
    dropzone.classList.add('drag-active');
  });
  dropzone.addEventListener('dragleave', function() {
    dropzone.classList.remove('drag-active');
  });
  dropzone.addEventListener('drop', function(e) {
    e.preventDefault();
    dropzone.classList.remove('drag-active');
    handleFiles(e.dataTransfer.files);
  });

  // Вставка из буфера Cmd+V
  window.addEventListener('paste', function(e) {
    if (!modal.open) return;
    var items = (e.clipboardData || e.originalEvent.clipboardData).items;
    if (!items) return;
    for (var i = 0; i < items.length; i++) {
      if (items[i].type.indexOf('image') !== -1) {
        var blob = items[i].getAsFile();
        if (blob) {
          uploadFileBlob(blob, 'Скриншот ' + new Date().toLocaleTimeString('ru-RU') + '.png');
        }
      }
    }
  });

  function handleFiles(files) {
    if (!files || !files.length) return;
    Array.from(files).forEach(function(f) {
      uploadFileBlob(f, f.name);
    });
  }

  function uploadFileBlob(file, fallbackName) {
    var reader = new FileReader();
    reader.onload = async function() {
      var base64 = reader.result;
      notify('Загрузка вложения…');
      try {
        var res = await api('/upload', 'POST', {
          name: file.name || fallbackName,
          type: file.type || 'application/octet-stream',
          base64: base64
        });
        modalPendingAttachments.push(res.attachment);
        renderModalAttachments();
        notify('Файл прикреплён');
      } catch (err) {
        notify('Не удалось загрузить файл: ' + err.message, true);
      }
    };
    reader.readAsDataURL(file);
  }

  // Переключение меню
  document.querySelectorAll('.sidebar-menu .nav-item').forEach(function(btn) {
    btn.addEventListener('click', function() {
      var isTasks = btn.dataset.feature === 'tasks';
      var view = document.getElementById('tasks-view');
      if (view) view.style.display = isTasks ? 'block' : 'none';
      if (isTasks && !isLoaded) loadTasks();
    });
  });

  if (location.hash === '#tasks' || localStorage.getItem('pdd-admin-feature') === 'tasks') {
    loadTasks();
  }
})();
`;
