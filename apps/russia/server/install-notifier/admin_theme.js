// Визуальная система всей панели. Загружается после стилей рабочих модулей,
// чтобы поверхности, типографика и действия имели одинаковую иерархию.
export const ADMIN_THEME_HTML = String.raw`
<style id="admin-design-system">
:root{
 --bg:#F4F5F7;--sidebar-bg:#FFFFFF;--card-bg:#FFFFFF;--card-border:transparent;
 --text:#17191E;--text-muted:#636D7B;--text-light:#555E6E;
 --primary:#0574F8;--primary-hover:#0065DE;--primary-subtle:#E8F1FF;
 --success:#15966B;--success-subtle:#E9F6EF;--danger:#D44C31;--danger-subtle:#FCEDE8;
 --surface-gray:#F1F3F6;--surface-hover:#E8ECF1;
 --admin-radius:20px;--admin-gap:16px;--admin-divider:#EDF0F3;
 --admin-type-page:clamp(24px,2.3vw,30px);
 --admin-type-dialog:clamp(20px,1.8vw,24px);
 --admin-type-section:18px;--admin-type-title:16px;
 --admin-type-body:14px;--admin-type-control:13px;--admin-type-caption:12px;
 --admin-type-metric:clamp(26px,2.4vw,34px);
 --admin-weight-medium:500;--admin-weight-semibold:600;
 --admin-leading-title:1.3;--admin-leading-body:1.5;
 --font:-apple-system,BlinkMacSystemFont,'Segoe UI',Inter,Roboto,sans-serif;
 color-scheme:light
}
body{display:block;overflow-x:visible;background:var(--bg);margin:0;color:var(--text);font-size:var(--admin-type-body);line-height:var(--admin-leading-body);font-family:var(--font);font-feature-settings:"cv11","ss01";min-height:100svh}
button,input,select,textarea{font-family:inherit}button,a,input,select,textarea{-webkit-tap-highlight-color:transparent}
button{letter-spacing:0}button:disabled{cursor:default;opacity:.45}button:focus-visible,a:focus-visible,summary:focus-visible,input:focus-visible,select:focus-visible,textarea:focus-visible{outline:2px solid #0574F8;outline-offset:3px}
.admin-wrapper {
 display:flex;
 width:100%;
 min-height:100dvh;
 margin:0;
 background:var(--bg);
 isolation:isolate;
}
.sidebar {
 width:clamp(184px,15vw,218px);
 flex:0 0 auto;
 align-self:flex-start;
 position:sticky;
 top:0;
 height:100dvh;
 background:var(--sidebar-bg);
 transition:width .18s ease;
}
.sidebar-brand{padding:26px 20px 28px;gap:8px;min-height:86px}.brand-info{gap:10px}.brand-info img{height:29px;width:29px;border-radius:8px;box-shadow:none}.admin-brand-name{font-size:15px;font-weight:650;letter-spacing:-.4px;white-space:nowrap;color:var(--text)}
.sidebar-toggle-btn{width:26px;height:26px;border:0;border-radius:50%;color:#9198A5}.sidebar-toggle-btn:hover{background:var(--surface-gray);border:0}
.sidebar-menu{gap:5px;padding:0 14px;flex:1;min-height:0;overflow-y:auto}.nav-item{width:100%;border:0;border-radius:12px;min-height:42px;padding:11px 14px;gap:11px;font-size:12.5px;font-weight:550;line-height:1.3;color:#7B8290;background:transparent;text-align:left}.nav-item svg{width:17px;height:17px;stroke-width:1.7;flex-shrink:0}.nav-item:hover{background:#F4F5F7;color:#17191E}.nav-item.active{background:#17191E;color:#fff;font-weight:600}.nav-item[data-feature="users"]{margin-top:18px}
.sidebar-footer{padding:16px 14px 20px}.btn-logout{justify-content:flex-start;background:transparent;color:#747B88;border-radius:11px;font-size:12px;font-weight:550;padding:10px 14px}.btn-logout:hover{background:#F4F5F7;color:#17191E}.sidebar.collapsed{width:68px}.sidebar.collapsed .admin-brand-name{display:none}.sidebar.collapsed .sidebar-brand{padding:22px 8px 18px}.sidebar.collapsed .brand-info img{width:30px!important;height:30px!important;box-shadow:none!important;border-radius:8px!important}.sidebar.collapsed .sidebar-toggle-btn{background:transparent!important;border:0!important;border-radius:50%!important}.sidebar.collapsed .nav-item{border-radius:12px;width:44px;height:44px}.sidebar.collapsed .nav-item[data-feature="users"]{margin-top:14px}.sidebar.collapsed .sidebar-footer{padding:16px 8px}.sidebar.collapsed .btn-logout{border-radius:12px}
.main-area,.content{width:100%;max-width:none;min-width:0;margin:0;padding:clamp(18px,1.8vw,30px) clamp(12px,2vw,32px) clamp(24px,2.5vw,40px);background:var(--bg)}
.top-bar,.header{min-height:44px;margin-bottom:clamp(16px,1.5vw,24px);gap:12px 20px;align-items:center;flex-wrap:wrap}.view-title,.page-title{font-size:29px;font-weight:580;line-height:1.2;letter-spacing:-1.1px}.top-actions{gap:8px;max-width:100%;margin-left:auto}.admin-data-state{font-size:11px;padding:0 8px;color:var(--text-muted);font-weight:450}.admin-data-state::before{width:5px;height:5px}.segmented{padding:4px;border-radius:12px;background:#E9ECF1}.segmented button{padding:7px 12px;font-size:11.5px;border-radius:9px;font-weight:550}.segmented button.active{background:#fff;color:var(--text);font-weight:650}.btn-icon{height:36px;width:36px;background:#fff;border-radius:11px;color:#6B7381}.btn-icon:hover{background:#E8ECF1}
.btn-action,.uv-btn,.uv-icon-btn{border:0;border-radius:10px;background:#F0F2F5;color:#343B49;font-size:12px;font-weight:550;min-height:34px;padding:8px 13px;line-height:1.25;box-shadow:none;transition:background .15s}.btn-action:hover,.uv-btn:hover,.uv-icon-btn:hover{background:#E6EAF0;color:#17191E}.btn-action.btn-primary,.btn-action.primary,.uv-btn.primary{background:var(--primary);color:#fff;font-weight:600}.btn-action.btn-primary:hover,.btn-action.primary:hover,.uv-btn.primary:hover{background:var(--primary-hover);color:#fff}.btn-action.btn-danger,.uv-btn.danger{background:var(--danger-subtle);color:var(--danger)}
.card,.an-card,.nt-card,.uv-card,.kpi-card,.tasks-kpi-card,.tasks-toolbar,.task-item,.task-card,.tasks-column,.tasks-kanban-col,.ln-card{border:0!important;box-shadow:none!important;border-radius:var(--admin-radius);background:#fff;min-width:0}
.card{padding:22px 24px;margin-bottom:16px}.card-head{gap:12px;align-items:center;flex-wrap:wrap;margin-bottom:18px}.card-title{font-size:15px;font-weight:600;letter-spacing:-.25px;line-height:1.35;gap:8px}.card-title svg{width:16px;height:16px;stroke-width:1.6;color:#747B88}.kpi-card{padding:20px 22px}.kpi-grid{gap:16px;margin-bottom:16px}.kpi-value,.kpi-val{font-size:32px;font-weight:580;letter-spacing:-1px;line-height:1.2}.kpi-label,.kpi-head{font-size:12px;text-transform:none;letter-spacing:0;font-weight:500;color:var(--text-muted)}
.form-label{font-size:11px;font-weight:550;text-transform:none;letter-spacing:0;color:#6D7583;margin-bottom:6px}.form-group{min-width:0}input:not([type="checkbox"]):not([type="radio"]):not([type="color"]):not([type="range"]),select,textarea{border:0;border-radius:10px;background:#F3F5F8;color:#242A35;min-height:36px;font-size:var(--admin-type-body);box-shadow:none}input:focus,select:focus,textarea:focus{background:#EEF2F8}.sc-input{border:0!important}.an-search{border:0;background:#F3F5F8}.an-clear{border:0;background:#F0F2F5}
input[type="checkbox"],input[type="radio"]{accent-color:#0574F8;box-shadow:none}.an-table,.ln-table,table{font-size:12.5px}.an-table th,table th{font-size:10px;font-weight:550;letter-spacing:.45px;color:var(--text-muted);text-transform:uppercase;background:transparent}.an-table td,table td{font-weight:500;padding-top:13px;padding-bottom:13px;border-color:var(--admin-divider)}.an-table-name{font-weight:550}.an-tabs,.uv-seg,.sc-tabs{gap:3px}.an-tabs,.uv-seg{background:#F0F2F6;border-radius:10px;padding:3px}.an-tabs button,.uv-seg button{border-radius:8px;padding:6px 11px;font-weight:550;font-size:11px}.an-tabs button.active,.uv-seg button.active{background:#fff;color:#242A35;box-shadow:none}.an-help summary{border:0;background:#F3F5F8;color:#8A92A0;font-size:10px}.an-help>div{border:0;box-shadow:0 10px 36px #17223618;border-radius:12px;color:#5E6878}.an-pagination button{border:0;background:#F0F2F5;border-radius:8px}.an-pagination span{font-size:11px}
/* Пользователи: выделяем состояние заполнением, не рамкой вокруг каждого числа. */
.uv-kpis{gap:12px;margin-bottom:18px}.uv-kpi{border:0;box-shadow:none;padding:19px 20px;border-radius:18px;background:#fff}.uv-kpi:hover{box-shadow:none;background:#EDF2FA}.uv-kpi.active{box-shadow:none;background:#17191E;color:#fff}.uv-kpi.active .uv-kpi-label{color:#B7BECA}.uv-kpi-label{font-size:11px;font-weight:500}.uv-kpi-value{font-size:28px;font-weight:600;letter-spacing:-.75px}.uv-toolbar{gap:8px;margin-bottom:12px}.uv-row{border-radius:10px;padding:14px 6px;gap:16px}.uv-row+.uv-row{box-shadow:none;border-top:1px solid #F1F3F6}.uv-head{font-size:10px;font-weight:550;letter-spacing:.4px}.uv-name{font-size:13px;font-weight:550}.uv-avatar{background:#EEF2F8;color:#69758A;font-weight:550}.uv-chip{font-size:10px;font-weight:550;border-radius:6px}.uv-sub,.uv-cell{font-size:11.5px}.uv-grid,.uv-col{gap:16px}.uv-card{padding:22px}.uv-card-title{font-size:13px;font-weight:600;text-transform:none;letter-spacing:-.2px;color:#333B48}.uv-stat{background:#F5F6F9}.uv-stat-v{font-size:22px;font-weight:600}.uv-hero-name{font-size:24px;font-weight:600}.uv-prem-status{font-size:22px;font-weight:600}.uv-preview{background:#F3F5F8;border-radius:10px;color:#636D7C}
/* Задачи: спокойная доска с цветом только на статусе/действии. */
.tasks-wrap{gap:16px}.tasks-kpi-grid{gap:12px}.tasks-kpi-card{padding:18px 20px;border:0;box-shadow:none;border-radius:18px}.tasks-kpi-card:hover{transform:none;box-shadow:none;background:#EDF2FA}.tasks-kpi-card.active{border:0;box-shadow:none;background:#17191E}.tasks-kpi-card.active .tasks-kpi-value{color:#fff}.tasks-kpi-card.active .tasks-kpi-label,.tasks-kpi-card.active .tasks-kpi-sub{color:#B7BECA}.tasks-kpi-label{text-transform:none;letter-spacing:0;font-size:11px;font-weight:500}.tasks-kpi-value{font-size:28px;font-weight:600}.tasks-kpi-icon{background:#F3F5F8!important;color:#7A8595!important;border-radius:50%}.tasks-kpi-card.active .tasks-kpi-icon{background:#30343D!important;color:#CCD3DE!important}.tasks-kpi-sub{font-size:11px;font-weight:400}.tasks-toolbar{padding:14px 16px}.tasks-toolbar-right{flex-wrap:wrap}.tasks-view-switch,.tasks-view-toggle{background:#F0F2F6;border-radius:10px;border:0;box-shadow:none}.tasks-kanban{gap:14px}.task-card,.task-item{border-radius:12px!important}.task-card:hover,.task-item:hover{box-shadow:none!important;transform:none!important;background:#F8FAFD}.task-card-title,.task-title{font-size:13px;font-weight:550}.task-priority,.task-badge{border:0;font-size:10px;font-weight:550}
/* Редакторы социальных площадок и уведомлений. */
.sc-chip{font-size:11px;font-weight:500;border-radius:7px;padding:5px 9px;background:#F2F4F7}.sc-chip.ok{color:#16805D;background:#EAF5EE}.sc-chip.bad{color:#BE4C32;background:#FBEDE8}.sc-tab{border:0;border-radius:9px;background:#F1F3F7;color:#7A8290;font-size:11.5px;padding:8px 11px;font-weight:550}.sc-tab.active{background:#17191E;color:#fff}.sc-row{border:0!important;border-radius:13px;box-shadow:none!important;background:#F6F7FA;padding:14px}.sc-row.sel{background:#E8F1FF;box-shadow:none!important}.sc-card{border:0!important;box-shadow:none!important;border-radius:14px}.sc-card:hover{box-shadow:none!important;transform:none}.sc-card.sel{box-shadow:none!important;background:#E8F1FF}.sc-card.sel .sc-poster{opacity:.85}.sc-pill{font-size:10px;font-weight:550}.sc-hint{font-size:11px;font-weight:400;color:#7A8290}.sc-modal{border:0;border-radius:22px;box-shadow:0 20px 80px #17223622;padding:26px}.nt-grid{gap:16px}.nt-card{padding:22px 24px;border-radius:20px}.nt-card h3{font-size:16px;font-weight:600;letter-spacing:-.3px}.nt-section{padding-top:18px;margin-top:18px;border-color:#F0F2F5}.nt-section h4{font-size:12px;font-weight:600;color:#495365}.nt-field>span{font-size:11px;font-weight:500;color:#717B8B}.nt-field small,.nt-hint{font-size:11px;color:#828A97}.nt-actions{gap:8px}.nt-preview{background:#F4F5F7;border:0;border-radius:16px}.nt-switch{border:0;box-shadow:none}.nt-modal{border:0;border-radius:22px;box-shadow:0 20px 80px #17223622}.nt-table-wrap{overflow:auto}.nt-history td{font-weight:450}.nt-history strong{font-weight:550}
/* Публикации разделяют ту же систему; тонкие линии остаются только в календаре и таблицах. */
#publications-view{--pb-line:#EDF0F3;--pb-muted:#747B88;--pb-bg:#F4F5F7;--pb-blue:#0574F8}
#publications-view .card{border:0!important;border-radius:20px;padding:22px 24px}.pb-panel,.pb-stat,#blog-view .bl-panel{border:0!important;border-radius:20px;box-shadow:none}.pb-channel,.pb-icon-btn{border:0!important}.pb-search,.pb-tools select{border:0!important}.pb-drawer{--pb-line:#EDF0F3;--pb-muted:#747B88}.pb-status{font-weight:500}.pb-plan-row>.pb-status{justify-self:start}.pb-drawer-preview{border-radius:14px}.pb-drawer h4{font-weight:600}.pb-empty strong,.bl-empty strong{font-weight:600}
/* Вторичные настройки открываются по запросу, не занимая весь первый экран. */
.admin-disclosure{background:#fff;border:0;border-radius:18px;margin-bottom:16px;min-width:0}.admin-disclosure>summary{display:flex;align-items:center;gap:10px;list-style:none;padding:18px 22px;font-size:13px;font-weight:550;cursor:pointer;color:#495365}.admin-disclosure>summary::-webkit-details-marker{display:none}.admin-disclosure>summary::before{content:'';width:6px;height:6px;border-right:1.5px solid #7B8594;border-bottom:1.5px solid #7B8594;transform:rotate(-45deg);transition:transform .15s;flex-shrink:0}.admin-disclosure[open]>summary::before{transform:rotate(45deg)}.admin-disclosure>summary>span{margin-left:auto;font-weight:450;font-size:11px;color:#89919F}.admin-disclosure-body{padding:0 22px 22px;min-width:0}.admin-disclosure-body>.nt-card{padding:0!important;margin:0!important}.admin-disclosure-body>.sc-hint{font-size:11px}
.ai-scope.admin-disclosure{margin:18px 0 0;padding:0;border-radius:0}.ai-scope.admin-disclosure>summary{padding:0;font-size:11px;font-weight:450}.ai-scope.admin-disclosure>summary::after{content:none}
.ai-access{margin-top:16px}
.task-badge.version,.task-badge.prio-high,.task-badge.prio-low{border:0}
.uv-row{border-radius:0}
.login-box input:focus-visible{outline:2px solid #0574F8;outline-offset:3px}
/* Ссылки: форма и таблицы с одной, лёгкой типографикой. */
#links-view .an-card{padding:22px 24px;margin-bottom:16px}#links-view .an-title{margin-bottom:20px;flex-wrap:wrap;font-size:15px;font-weight:600;letter-spacing:-.2px}#links-view .an-label{font-size:11px;font-weight:500;color:#747B88}.ln-chips{gap:6px}.ln-chip{padding:7px 11px 7px 7px;border-radius:9px;font-size:12px;font-weight:500;background:#F1F3F6}.ln-chip.text{padding:8px 12px}.ln-chip.active{background:#17191E;color:#fff}.ln-chip .an-logo,.ln-chip .an-mono{width:22px;height:22px;border-radius:6px}.ln-input{padding:10px 12px;font-size:12.5px;font-weight:450;border-radius:10px}.ln-result{background:#F4F6F9;border-radius:12px;gap:6px}.ln-url{font-size:12px;font-weight:500;flex-basis:240px}.ln-btn{min-height:34px;border-radius:9px;padding:8px 12px;font-size:12px;font-weight:550}.ln-seg{border-radius:10px;padding:3px}.ln-seg button{font-size:11px;font-weight:550;padding:6px 10px}#links-view .ln-table th{font-size:10px;font-weight:550;color:#89919F;padding-bottom:12px}#links-view .ln-table td{font-size:13px;font-weight:550;border-color:#EDF0F3;padding-top:13px;padding-bottom:13px}.ln-who{gap:10px}.ln-name{font-size:12.5px;font-weight:550;line-height:1.45}.ln-sub{font-size:11px;font-weight:450;line-height:1.5}#links-view .ln-sub-row td{font-size:11px;font-weight:450}.ln-error{font-size:12px;font-weight:500}
/* Доска сохраняет порядок статусов и прокручивается внутри раздела. */
.tasks-board{grid-template-columns:none;grid-auto-flow:column;grid-auto-columns:minmax(230px,1fr);overflow-x:auto;max-width:100%;padding-bottom:10px;scrollbar-width:thin;scroll-snap-type:x proximity}.tasks-col{border:0;box-shadow:none;background:#EDF0F4;border-radius:16px;min-width:0;min-height:350px;scroll-snap-align:start}.tasks-col.drag-over{background:#DBEAFE;border:0;box-shadow:none}.tasks-col-pill{font-size:11px;font-weight:550;border-radius:8px;padding:5px 8px}.tasks-col-pill .col-emoji,.tasks-kpi-icon,.tasks-kpi-sub{display:none}.tasks-col-pill .col-count{font-weight:550;font-size:10px;border-radius:5px;background:#FFFFFF80}.tasks-col-empty{border:0;background:transparent;font-size:11px;color:#98A0AD}.tasks-col-quick-add{border:0;border-radius:10px;font-size:11.5px;font-weight:500;background:#FFFFFF80}.tasks-col-quick-add:hover,.tasks-col-add-btn:hover{box-shadow:none;background:#fff}.tasks-list-wrap{border:0;box-shadow:none;border-radius:18px}.tasks-table td{font-size:12px;font-weight:450;border-color:#EDF0F3}.tasks-table th{font-size:10px;font-weight:550}.tasks-segmented{border-radius:10px;background:#F0F2F6}.tasks-segmented button{font-size:11.5px;font-weight:550;padding:7px 10px}.tasks-segmented button.active{box-shadow:none;background:#17191E;color:#fff}.tasks-search-wrap{min-width:160px}.tasks-select-pill,.tasks-archive-toggle,.btn-create-task{font-size:11.5px;font-weight:550;min-height:34px;border:0;box-shadow:none}.btn-create-task:hover{box-shadow:none;transform:none}.task-card-desc{font-size:11.5px;color:#7B8594}.task-modal{border-radius:22px;box-shadow:0 20px 80px #17223622;padding:26px;max-height:90svh;overflow-y:auto}.task-modal::backdrop{background:#17223655;backdrop-filter:blur(3px)}.task-modal-title{font-weight:600;font-size:20px}.task-form-group{min-width:0}.task-form-group label{font-size:11px;font-weight:550;text-transform:none;letter-spacing:0}.task-dropzone{border:0;background:#F3F5F8;padding:20px}.task-modal-att-item{border:0}.task-modal-foot{gap:8px;flex-wrap:wrap}.task-form-input:focus,.task-form-select:focus,.task-textarea:focus{box-shadow:none}
/* Переключатели уведомлений и формы подключения. */
.nt-controls{gap:12px;margin-bottom:16px}.nt-control{border:0;padding:18px 20px;border-radius:18px;min-width:0}.nt-control strong{font-size:12px;font-weight:550;line-height:1.4}.nt-control small{font-size:11px;font-weight:400;margin-top:4px}.nt-seg{background:#F0F2F6;border-radius:12px;padding:4px;gap:3px}.nt-seg label{font-size:11.5px;font-weight:550;padding:9px 5px}.nt-seg label small{font-size:10px;font-weight:450}.nt-seg label:has(input:checked){background:#17191E;color:#fff;box-shadow:none}.nt-image input[type=url]{min-width:0}.sc-modal input,.sc-modal select{min-width:0}.sc-hint b{font-weight:550}
/* Диалоги — единственное место с тенью для отделения от рабочего контекста. */
#login-overlay{background:#E8EBEF;backdrop-filter:none}.login-box{border:0;border-radius:24px;box-shadow:none;padding:36px}.login-box h2{font-weight:600;font-size:26px;letter-spacing:-.8px}.login-box p{font-size:12px;color:#818A99}.login-box img{box-shadow:none}#sidebar-tooltip-el{box-shadow:none;background:#17191E;border-radius:9px;font-size:11px;font-weight:450}
@media(max-width:1200px){.nt-controls{grid-template-columns:repeat(2,minmax(0,1fr))}}
@media(max-width:1100px){.view-title{font-size:26px}.admin-data-state{display:none}.uv-row{gap:12px;grid-template-columns:minmax(0,1fr) auto 16px}.uv-row>.uv-hide-sm{display:none}.nt-grid{grid-template-columns:minmax(0,1fr)}.nt-sticky{position:static}}
@media(max-width:900px){
 .admin-wrapper{flex-direction:column}
 .sidebar,.sidebar.collapsed{
  display:grid;grid-template-columns:auto minmax(0,1fr) auto;align-items:center;
  width:auto;align-self:stretch;height:auto;position:static;transition:none;padding:6px clamp(12px,2vw,18px);gap:0 12px
 }
 .sidebar-brand,.sidebar.collapsed .sidebar-brand{min-height:0;padding:0;flex-direction:row;justify-content:flex-start}
 .sidebar.collapsed .brand-info{width:auto!important;justify-content:flex-start!important}
 .admin-brand-name,.sidebar.collapsed .admin-brand-name{display:inline;font-size:14px}
 .brand-info img,.sidebar.collapsed .brand-info img{width:27px!important;height:27px!important}
 .sidebar-toggle-btn,.sidebar.collapsed .sidebar-toggle-btn,#sidebar-tooltip-el{display:none!important}
 .sidebar-menu,.sidebar.collapsed .sidebar-menu{
  flex-direction:row;align-items:center;min-width:0;overflow-x:auto;overflow-y:hidden;
  padding:4px 0;gap:4px;scrollbar-width:none
 }
 .sidebar-menu::-webkit-scrollbar{display:none}
 .nav-item,.sidebar.collapsed .nav-item{
  flex:none;width:auto;height:40px;min-height:40px;padding:8px 11px;justify-content:center;
  gap:7px;border-radius:10px;font-size:12px;white-space:nowrap
 }
 .nav-item svg{width:15px;height:15px}
 .sidebar.collapsed .nav-item span{display:inline!important}
 .nav-item[data-feature="users"],.sidebar.collapsed .nav-item[data-feature="users"]{margin:0}
 .sidebar-footer,.sidebar.collapsed .sidebar-footer{display:flex;margin:0;padding:0}
 .sidebar-footer .btn-logout,.sidebar.collapsed .sidebar-footer .btn-logout{width:38px;height:38px;padding:0;justify-content:center;background:#F3F5F8}
 .sidebar-footer .btn-logout span{display:none}
}
@media(max-width:600px){
 .sidebar,.sidebar.collapsed{grid-template-columns:minmax(0,1fr) auto;padding-block:8px 4px}
 .sidebar-footer{grid-area:1/2}
 .sidebar-menu{grid-column:1/-1;grid-row:2}
 .top-actions{width:100%;gap:6px}
 .segmented{flex:1;display:flex}.segmented button{flex:1;padding:8px 6px;font-size:11px;white-space:nowrap}
 .btn-icon{width:36px;height:36px;flex-shrink:0}
}
@media(max-width:760px){
 .view-title,.page-title{font-size:clamp(23px,4.4vw,27px);font-weight:580;letter-spacing:-.8px}
 .card,.nt-card,.uv-card{padding:18px!important;border-radius:17px!important}.card-head{margin-bottom:16px;gap:10px}.card-title{font-size:14px}.btn-action{font-size:11px;padding:8px 11px;min-height:32px}.kpi-grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.kpi-card{padding:17px}.kpi-value{font-size:28px}.uv-kpi{padding:16px;border-radius:16px}.uv-kpi-value{font-size:26px}.uv-kpis{gap:10px}.uv-toolbar{gap:8px}.uv-grid,.uv-col{gap:12px}.uv-hero-name{font-size:21px}.nt-grid{grid-template-columns:minmax(0,1fr)}.nt-sticky{position:static!important}.nt-row{grid-template-columns:minmax(0,1fr)}.nt-field,.nt-image{min-width:0}.nt-image{flex-wrap:wrap}.tasks-toolbar{padding:12px}.tasks-toolbar-left,.tasks-toolbar-right{min-width:0;width:100%;flex-wrap:wrap}.tasks-toolbar-right{justify-content:space-between}.tasks-kpi-card{padding:16px}.tasks-kpi-value{font-size:26px}
 #publications-view .card{padding:18px!important;border-radius:17px}.sc-row{padding:12px}.sc-modal{padding:20px;border-radius:20px}.pb-drawer{padding:22px}.pb-panel{border-radius:17px!important}
 #links-view .an-card{padding:18px}#links-view .an-title{gap:10px;margin-bottom:17px}.ln-chip{font-size:11px}.ln-chips{gap:5px}.ln-url{flex-basis:100%;padding:4px 0 8px}.ln-btn{font-size:11px}.ln-who{gap:7px}.ln-name{font-size:11.5px}.ln-sub{font-size:10px}#links-view .ln-table td{font-size:12px}#links-view .ln-table th{font-size:9px}.ln-icon{width:27px;height:30px}
 .admin-disclosure>summary{padding:16px 18px}.admin-disclosure-body{padding:0 18px 18px}.tasks-search-wrap{max-width:none;flex-basis:100%}.tasks-board{grid-auto-columns:minmax(235px,1fr)}.tasks-kpi-grid{grid-template-columns:repeat(2,minmax(0,1fr))}.task-form-row{grid-template-columns:minmax(0,1fr)}.task-modal{padding:20px;width:calc(100vw - 24px)}.nt-image{display:grid;grid-template-columns:54px minmax(0,1fr) auto}.nt-image input[type=url]{grid-column:2/4}.nt-image #nt-upload{grid-column:2;justify-content:center}.nt-image #nt-image-clear{grid-column:3}.nt-thumb{grid-row:1/3}.nt-control{padding:16px}.nt-row3{grid-template-columns:65px minmax(0,1fr)}
 .pb-month-nav{flex-wrap:wrap;min-width:0}.pb-channel{min-height:34px}.bl-icon,.pb-icon-btn{min-width:34px;min-height:34px}.ai-access>summary{flex-wrap:wrap}.ai-access>summary>span{margin-left:16px}
 .uv-row{grid-template-columns:minmax(0,1fr) 16px;gap:8px 10px;padding:16px 0}.uv-row>.uv-user{grid-column:1;grid-row:1}.uv-row>div:nth-child(3){grid-column:1;grid-row:2;padding-left:47px;min-width:0}.uv-row>.uv-chev{grid-column:2;grid-row:1/3}.uv-head{display:none}.uv-row .uv-chip{max-width:100%;white-space:normal}.uv-row .uv-sub{font-size:11px}

}
@media(max-width:440px){.nt-controls{grid-template-columns:minmax(0,1fr)}.sc-card .form-group{min-width:0}.sc-modal [style*="minmax(230px"],#social-view [style*="minmax(230px"],#threads-view [style*="minmax(230px"]{grid-template-columns:minmax(0,1fr)!important}}
/* Text roles shared by the admin views. The phone previews and chart axes
   keep their own typography because they represent other viewing surfaces. */
@media(max-width:760px){:root{--admin-type-section:17px}}
#analytics-view{--an-muted:var(--text-muted)}
#economy-view{--ec-muted:var(--text-muted)}
#publications-view{--pb-muted:var(--text-muted)}
#promocodes-view,#pc-dialog,#pc-history-dialog{--pc-muted:var(--text-muted)}
.view-title,.page-title{
 font-size:var(--admin-type-page);font-weight:var(--admin-weight-semibold);line-height:1.2;letter-spacing:-.035em
}
.card-title,#analytics-view .an-title,#links-view .an-title,.uv-card-title,.ai-card-title,
#economy-view .ec-head h2,#blog-view .bl-heading,.pb-month-title,.nf-hist-h h3,.nt-card h3{
 font-size:var(--admin-type-section);font-weight:var(--admin-weight-semibold);line-height:var(--admin-leading-title);letter-spacing:-.02em
}
.nf-sec h4,.nt-section h4,.ec-plan-title,.pb-empty strong,.bl-empty strong{
 font-size:var(--admin-type-title);font-weight:var(--admin-weight-semibold);line-height:var(--admin-leading-title)
}
.task-modal-title,.pc-dialog-title,.sc-modal .sc-dialog-title,.nf-modal h3,.pb-drawer h4,#ec-dialog h2{
 font-size:var(--admin-type-dialog);font-weight:var(--admin-weight-semibold);line-height:var(--admin-leading-title);letter-spacing:-.025em
}
.kpi-value,.kpi-val,.an-big,.uv-kpi-value,.tasks-kpi-value,.ai-kpi-value:not(.ai-kpi-model),
.pc-kpis strong,.pb-stat strong{
 font-size:var(--admin-type-metric);font-weight:var(--admin-weight-semibold);line-height:1.18;letter-spacing:-.035em;font-variant-numeric:tabular-nums
}
.kpi-label,.kpi-head,.an-kpi-top,.uv-kpi-label,.tasks-kpi-label,.ai-kpi-label,.pc-kpis .pc-muted,
.pb-stat span,.ec-kpi-label,.form-label,.ai-field-label,.task-form-group label,.nt-field>span,.uv-label,
.ec-field,.pc-field,.pb-field,#links-view .an-label{
 font-size:var(--admin-type-control);font-weight:var(--admin-weight-medium);line-height:1.4
}
.nav-item,.sidebar.collapsed .nav-item,.btn-logout,.btn-action,.uv-btn,.ln-btn,.segmented button,.uv-seg button,
.an-tabs button,#an-usage-groups button,.ln-seg button,.tasks-segmented button,.tasks-select-pill,.btn-create-task,
.sc-tab,#social-view .sc-bulk .btn-action,#blog-view .bl-head-actions .btn-action,.pb-tabs button,.nf-tabs button,
.nf-btn,.tasks-archive-toggle,#economy-view .ec-navigation button,#economy-view .ec-link{
 font-size:var(--admin-type-control);font-weight:var(--admin-weight-semibold);line-height:1.35
}
.uv-toolbar :is(input,select),.task-form-group :is(input:not([type=checkbox]),select,textarea),
.ec-field :is(input,select),.pc-field :is(input,textarea),#notifications-view .nf-in :is(input,textarea),
.ai-input,.sc-input,.pb-field input,.pb-search,.ln-input{
 font-size:var(--admin-type-body);line-height:var(--admin-leading-body)
}
.uv-name,.task-card-title,.task-title,.ln-name,#social-view .sc-title,#blog-view .bl-title,
.pb-row-title,.pc-user-name,#ec-receipts-body .ec-row-title,.ec-recent-text strong{
 font-size:var(--admin-type-body);font-weight:var(--admin-weight-semibold);line-height:var(--admin-leading-body)
}
.an-table,.ec-table,.pc-table,.tasks-table td,#links-view .ln-table td,.uv-cell,.pb-detail-text,.uv-kv,.nf-result{
 font-size:var(--admin-type-body);line-height:var(--admin-leading-body)
}
.an-table th,.tasks-table th,.pc-table th,#links-view .ln-table th,#economy-view .ec-table th,.uv-head{
 font-size:var(--admin-type-caption);font-weight:var(--admin-weight-semibold);line-height:1.35;letter-spacing:.025em
}
.admin-data-state,.ec-caption,.an-caption,.an-legend,.an-period,.an-growth-grid .an-metric-summary>span,
.ec-breakdown-grid h3,.ec-recent-text small,#ec-receipts-body .ec-sub,.ec-form-note,.ec-register-note,
.uv-meta,.uv-row .uv-sub,.uv-note-state,.tasks-kpi-sub,.task-card-desc,.ai-kpi-footer,.ln-sub,#links-view .ln-sub-row td,
.pb-row-meta,.pb-drawer-note,#blog-view .bl-caption,#blog-view .bl-meta,.sc-hint,.nf-note,.nf-msg small,.pc-field small{
 font-size:var(--admin-type-caption);line-height:var(--admin-leading-body)
}
@media(prefers-reduced-motion:reduce){*,*::before,*::after{transition:none!important;animation:none!important;scroll-behavior:auto!important}}
</style>`;

export const ADMIN_THEME_CLIENT_JS = String.raw`
// Горизонтальное меню телефона всегда показывает выбранный раздел.
(function(){
 var menu=document.querySelector('.sidebar-menu');
 var revealTimer;
 function revealCurrent(){if(!menu||getComputedStyle(menu).flexDirection!=='row')return;var button=menu.querySelector('.nav-item.active');if(button)menu.scrollTo({left:menu.scrollLeft+button.getBoundingClientRect().left-menu.getBoundingClientRect().left-(menu.clientWidth-button.offsetWidth)/2,behavior:'auto'});}
 function restoreCurrent(){revealCurrent();requestAnimationFrame(function(){requestAnimationFrame(revealCurrent);});clearTimeout(revealTimer);revealTimer=setTimeout(revealCurrent,150);}
 document.querySelectorAll('.sidebar-menu .nav-item').forEach(function(button){button.addEventListener('click',function(){requestAnimationFrame(revealCurrent);});});
 if(menu)new MutationObserver(function(){requestAnimationFrame(revealCurrent);}).observe(menu,{subtree:true,attributes:true,attributeFilter:['class']});
 window.addEventListener('load',restoreCurrent);window.addEventListener('pageshow',restoreCurrent);window.addEventListener('resize',revealCurrent);
 restoreCurrent();
})();
`;
