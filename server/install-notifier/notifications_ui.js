export const NOTIFICATIONS_NAV_HTML = `<button class="nav-item" data-feature="notifications"><svg viewBox="0 0 24 24" width="18" height="18" fill="none" stroke="currentColor" stroke-width="2"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg><span>Уведомления</span></button>`;

// Illustrations of where a message appears (tiles of the editor).
const ART = {
  push: '<svg viewBox="0 0 56 40" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="16" y="2" width="24" height="36" rx="5"/><rect x="19.5" y="9" width="17" height="7" rx="2" fill="currentColor" fill-opacity=".18"/><path d="M22 12h9M22 14h6" stroke-width="1.2"/><path d="M8 13a6 6 0 0 1 3-5M48 13a6 6 0 0 0-3-5" stroke-linecap="round"/></svg>',
  news: '<svg viewBox="0 0 56 40" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="16" y="2" width="24" height="36" rx="5"/><rect x="19.5" y="8" width="17" height="6" rx="1.6" fill="currentColor" fill-opacity=".18"/><rect x="19.5" y="17" width="17" height="6" rx="1.6"/><rect x="19.5" y="26" width="17" height="6" rx="1.6"/><circle cx="35" cy="9" r="1.8" fill="currentColor" stroke="none"/></svg>',
  popup: '<svg viewBox="0 0 56 40" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="16" y="2" width="24" height="36" rx="5"/><rect x="16.8" y="2.8" width="22.4" height="34.4" rx="4.2" fill="currentColor" fill-opacity=".08" stroke="none"/><rect x="19" y="11" width="18" height="17" rx="3" fill="currentColor" fill-opacity=".18"/><path d="M22 23h12" stroke-width="2.2" stroke-linecap="round"/></svg>',
  banner: '<svg viewBox="0 0 56 40" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="16" y="2" width="24" height="36" rx="5"/><rect x="19.5" y="7" width="17" height="10" rx="2" fill="currentColor" fill-opacity=".18"/><path d="M20 21h16M20 25h16M20 29h10" stroke-width="1.2" stroke-opacity=".45"/></svg>',
};
const LAYOUT_ART = {
  standard: '<svg viewBox="0 0 28 22" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="2" y="1" width="24" height="20" rx="3"/><rect x="2" y="1" width="24" height="9" rx="3" fill="currentColor" fill-opacity=".25"/><path d="M6 14h12M6 17h8"/></svg>',
  cover: '<svg viewBox="0 0 28 22" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="2" y="1" width="24" height="20" rx="3"/><rect x="2" y="1" width="24" height="14" rx="3" fill="currentColor" fill-opacity=".25"/><path d="M6 18h12"/></svg>',
  compact: '<svg viewBox="0 0 28 22" fill="none" stroke="currentColor" stroke-width="1.4"><rect x="2" y="1" width="24" height="20" rx="3"/><rect x="6" y="5" width="6" height="6" rx="1.5" fill="currentColor" fill-opacity=".25"/><path d="M6 14h14M6 17h9"/></svg>',
};
const tile = (value, label) => `<label class="nf-tile"><input type="radio" name="nt-place" value="${value}">${ART[value]}<b>${label}</b></label>`;
const chip = (name, value, label, type = 'radio') => `<label class="nf-chip"><input type="${type}" name="${name}" value="${value}"><span>${label}</span></label>`;

export const NOTIFICATIONS_VIEW_HTML = `
<div id="notifications-view" style="display:none">
<style>
#notifications-view{--nf-line:#E9ECF1;--nf-soft:#F4F6F9;--nf-warn:#C77700}#notifications-view [hidden]{display:none!important}
#notifications-view .nf-card,#notifications-view .nt-card{background:#fff;border-radius:20px;padding:24px}
.nf-tile input,.nf-chip input,.nf-seg input,.nf-push input{position:absolute;opacity:0;pointer-events:none}
.nf-push i{width:36px;height:22px;flex-shrink:0;border-radius:20px;background:#DDE1E9;position:relative;transition:background .15s}
.nf-push i:before{content:'';position:absolute;top:3px;left:3px;width:16px;height:16px;border-radius:50%;background:#fff;transition:transform .15s;box-shadow:0 1px 2px rgba(0,0,0,.15)}
.nf-push input:checked~i{background:var(--primary)}.nf-push input:checked~i:before{transform:translateX(14px)}
.nf-push input:focus-visible~i{outline:2px solid var(--primary);outline-offset:2px}
.nf-grid{display:grid;grid-template-columns:minmax(0,1fr) 380px;gap:16px;align-items:start;margin-bottom:16px}
.nf-sec{padding:20px 0;border-top:1px solid var(--nf-line)}.nf-sec:first-child{padding-top:0;border-top:0}
.nf-sec h4{margin:0 0 12px;font-size:12px;font-weight:600;color:var(--text-muted)}
.nf-push{display:flex;align-items:center;gap:14px;padding:12px 16px 12px 12px;border-radius:16px;background:var(--nf-soft);cursor:pointer;position:relative;margin-bottom:10px;color:var(--text-muted)}
.nf-push svg{width:56px;height:40px;flex-shrink:0}.nf-push span{flex:1;min-width:0}.nf-push b{display:block;font-size:14px;color:var(--text)}.nf-push small{display:block;font-size:12px;margin-top:2px}
.nf-push:has(input:checked){background:var(--primary-subtle);color:var(--primary)}.nf-push:has(input:disabled){cursor:not-allowed;opacity:.6}
.nf-tiles{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px}
.nf-tile{position:relative;display:flex;flex-direction:column;align-items:center;gap:6px;padding:14px 8px 12px;border-radius:16px;border:1.5px solid var(--nf-line);cursor:pointer;color:#9AA2B1;text-align:center}
.nf-tile svg{width:56px;height:40px}.nf-tile b{font-size:13px;font-weight:600;color:var(--text)}
.nf-tile:has(input:checked){border-color:var(--primary);color:var(--primary);background:#F7FAFF}.nf-tile:has(input:focus-visible){outline:2px solid var(--primary);outline-offset:2px}
.nf-note{margin:10px 0 0;font-size:12px;color:var(--text-muted)}.nf-note:empty{display:none}
.nf-drop{display:flex;align-items:center;gap:14px;border:1.5px dashed #CDD3DD;border-radius:16px;padding:14px;cursor:pointer;color:var(--text-muted);font-size:13px;transition:border-color .15s,background .15s}
.nf-drop:hover,.nf-drop.over{border-color:var(--primary);background:#F7FAFF}.nf-drop svg{flex-shrink:0}
.nf-drop.has{cursor:default;border-style:solid;border-color:var(--nf-line)}.nf-drop img{width:64px;height:64px;object-fit:contain;border-radius:12px;background:var(--nf-soft);flex-shrink:0}
.nf-drop b{display:block;color:var(--text);font-size:13px}.nf-drop .nf-grow{min-width:0}.nf-drop small{display:block;margin-top:2px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.nf-grow{flex:1;min-width:0}.nf-ratio{width:56px;height:44px;display:flex;align-items:center;justify-content:center;flex-shrink:0;color:#9AA2B1}.nf-ratio i{display:block;border:1.6px dashed currentColor;border-radius:4px}.nf-drop small.ok{color:var(--success)}.nf-drop small.warn{color:var(--nf-warn)}
.nf-link{border:0;background:none;color:var(--primary);font:inherit;font-size:12px;font-weight:600;cursor:pointer;padding:6px 8px;border-radius:8px}.nf-link:hover{background:var(--primary-subtle)}.nf-link.danger{color:var(--danger)}.nf-link.danger:hover{background:var(--danger-subtle)}
.nf-seg{display:inline-flex;gap:4px;background:var(--nf-soft);border-radius:12px;padding:3px;margin-top:10px}
.nf-seg label{position:relative;display:flex;align-items:center;gap:6px;padding:6px 10px;border-radius:9px;cursor:pointer;font-size:12px;font-weight:550;color:var(--text-muted)}
.nf-seg svg{width:22px;height:18px}.nf-seg label:has(input:checked){background:#fff;color:var(--text);box-shadow:0 1px 3px rgba(16,24,40,.1)}
.nf-in{position:relative;margin-top:10px}
#notifications-view .nf-in input,#notifications-view .nf-in textarea,#notifications-view .nf-row input,#notifications-view .nf-row select,#notifications-view .nf-when input{width:100%;box-sizing:border-box;border:1.5px solid var(--nf-line);border-radius:12px;background:#fff;padding:11px 14px;font:inherit;font-size:14px;color:var(--text);outline:none;transition:border-color .15s}
#notifications-view .nf-in input{padding-right:64px;font-weight:600}#notifications-view .nf-in textarea{min-height:96px;resize:vertical;line-height:1.5;padding-bottom:26px}
#notifications-view .nf-in input:focus,#notifications-view .nf-in textarea:focus,#notifications-view .nf-row input:focus,#notifications-view .nf-row select:focus,#notifications-view .nf-when input:focus{border-color:var(--primary)}
.nf-count{position:absolute;right:12px;bottom:12px;font-size:11px;color:#A3AAB6;font-variant-numeric:tabular-nums;pointer-events:none}.nf-in input~.nf-count{top:50%;bottom:auto;transform:translateY(-50%)}
.nf-count.warn{color:var(--nf-warn)}.nf-count.over{color:var(--danger);font-weight:700}
.nf-row{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:10px}.nf-row+.nf-row{margin-top:10px}.nf-row [hidden]{display:none}
.nf-swatches{display:flex;gap:8px;align-items:center;margin-top:12px}.nf-swatch{width:24px;height:24px;border-radius:50%;border:2px solid #fff;box-shadow:0 0 0 1px #D9DEE6;cursor:pointer;padding:0}.nf-swatch.on{box-shadow:0 0 0 2px var(--text)}
.nf-swatches input[type=color]{width:28px;height:28px;padding:0;border:0;background:none;cursor:pointer}.nf-swatches[hidden]{display:none}
.nf-two{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:24px}
.nf-chips{display:flex;flex-wrap:wrap;gap:6px}.nf-chips+.nf-chips{margin-top:8px}.nf-chips[hidden]{display:none}
.nf-chip{position:relative}.nf-chip span{display:inline-flex;align-items:center;gap:5px;padding:7px 12px;border-radius:10px;background:var(--nf-soft);font-size:12px;font-weight:550;color:#4A5262;cursor:pointer}
.nf-chip span svg{width:13px;height:13px}.nf-chip input:checked+span{background:var(--text);color:#fff}.nf-chip input:disabled+span{opacity:.4;cursor:not-allowed}.nf-chip input:focus-visible+span{outline:2px solid var(--primary);outline-offset:2px}
.nf-when{margin-top:8px}.nf-when[hidden]{display:none}
.nf-bar{display:flex;align-items:center;gap:8px;flex-wrap:wrap;padding-top:20px;border-top:1px solid var(--nf-line)}
.nf-btn{border:0;border-radius:12px;padding:12px 18px;font:inherit;font-size:13px;font-weight:600;cursor:pointer;background:var(--nf-soft);color:var(--text);display:inline-flex;align-items:center;gap:8px}
.nf-btn:hover{background:#E9EDF2}.nf-btn.primary{background:var(--primary);color:#fff}.nf-btn.primary:hover{background:var(--primary-hover)}.nf-btn:disabled{opacity:.45;cursor:not-allowed}
.nf-btn.ghost{background:none;color:var(--text-muted)}.nf-btn.ghost:hover{background:var(--nf-soft)}
.nf-recips{display:flex;flex-wrap:wrap;gap:6px;align-items:center;min-width:0;order:-1;flex-basis:100%;margin-bottom:4px}.nf-rc{position:relative;display:inline-flex;align-items:center;max-width:220px;border-radius:10px;background:var(--nf-soft);font-size:12px;color:#4A5262}
.nf-rc input{position:absolute;opacity:0;pointer-events:none}.nf-rc span{padding:7px 4px 7px 10px;cursor:pointer;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.nf-rc span:before{content:'';display:inline-block;width:12px;height:12px;border-radius:4px;border:1.5px solid #A3AAB6;margin-right:6px;vertical-align:-2px;box-sizing:border-box}
.nf-rc:has(input:checked){background:var(--primary-subtle);color:var(--primary)}.nf-rc:has(input:checked) span:before{background:var(--primary) url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 12 12'%3E%3Cpath d='M3 6.2l2 2 4-4.4' fill='none' stroke='white' stroke-width='1.8'/%3E%3C/svg%3E") center/10px no-repeat;border-color:var(--primary)}
.nf-rc:has(input:focus-visible){outline:2px solid var(--primary);outline-offset:2px}.nf-rc button{border:0;background:none;color:inherit;opacity:.55;cursor:pointer;padding:6px 8px 6px 2px;font-size:12px}.nf-rc button:hover{opacity:1}
.nf-rc-add{border:1px dashed #CDD3DD;background:none;border-radius:10px;padding:6px 10px;font:inherit;font-size:12px;font-weight:600;color:var(--text-muted);cursor:pointer}.nf-rc-add:hover{border-color:var(--primary);color:var(--primary)}
.nf-result{font-size:13px;margin:12px 0 0;color:var(--success)}.nf-result:empty{display:none}
#notifications-view .nt-error{color:var(--danger);font-size:13px;margin:0 0 12px}#notifications-view .nt-error:empty{display:none}
.nf-preview{position:sticky;top:20px;padding:16px!important}
.nf-tabs{display:flex;gap:4px;background:var(--nf-soft);border-radius:12px;padding:3px}.nf-tabs button{flex:1;border:0;background:none;border-radius:9px;padding:8px 6px;font:inherit;font-size:12px;font-weight:600;color:var(--text-muted);cursor:pointer}
.nf-tabs button.on{background:#fff;color:var(--text);box-shadow:0 1px 3px rgba(16,24,40,.1)}.nf-tabs button[hidden]{display:none}
.nf-os{display:flex;justify-content:center;gap:16px;margin:12px 0 0}.nf-os[hidden]{display:none}.nf-os button{border:0;background:none;font:inherit;font-size:12px;font-weight:600;color:#A3AAB6;cursor:pointer;display:inline-flex;align-items:center;gap:5px;padding:4px}.nf-os button svg{width:14px;height:14px}.nf-os button.on{color:var(--text)}
.nf-phone{margin:14px auto 0;width:284px;height:584px;border-radius:46px;background:#14161B;padding:9px;box-sizing:border-box;box-shadow:0 18px 40px -18px rgba(16,24,40,.45)}
.nf-screen{width:100%;height:100%;border-radius:38px;overflow:hidden;position:relative;background:#F8F9FA;font-family:-apple-system,BlinkMacSystemFont,'SF Pro Text',Roboto,sans-serif;color:#121212}
.nf-screen *{box-sizing:border-box}
.l1{display:block;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}.lc{display:-webkit-box;-webkit-box-orient:vertical;overflow:hidden;overflow-wrap:anywhere}
.ph-st{height:40px;display:flex;align-items:center;justify-content:space-between;padding:6px 26px 0;font-size:12px;font-weight:600}.ph-st i{width:52px;height:6px}
.lk{height:100%;background:linear-gradient(160deg,#5B7FD6 0%,#8E7BD8 45%,#E0A1B8 100%);color:#fff}.lk.an{background:linear-gradient(170deg,#1F2A44,#3C4C78 60%,#6F7FA8)}
.lk-date{text-align:center;font-size:13px;font-weight:550;opacity:.9;margin-top:6px}.lk-time{text-align:center;font-size:62px;font-weight:600;letter-spacing:-2px;line-height:1.05;margin-bottom:18px}
.lk-cap{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;opacity:.75;margin:12px 16px 6px}
.in{margin:0 9px;border-radius:18px;background:rgba(255,255,255,.72);backdrop-filter:blur(14px);-webkit-backdrop-filter:blur(14px);color:#111;padding:10px;display:flex;gap:9px}
.in img.ic{width:30px;height:30px;border-radius:7px;flex-shrink:0}.in .c{flex:1;min-width:0;font-size:12px;line-height:1.32}.in .h{display:flex;gap:6px;align-items:baseline}.in .h b{flex:1;min-width:0}.in .h span{font-size:10.5px;color:rgba(0,0,0,.45);flex-shrink:0}
.in p{margin:0}.in .th{width:32px;height:32px;border-radius:6px;background:#ddd center/cover;flex-shrink:0;align-self:center}
.in.big{flex-direction:column;gap:0;padding:0;overflow:hidden}.in .pic{display:block;width:100%;height:auto;background:#ddd}.in .row{display:flex;gap:9px;padding:10px}
.an-n{margin:0 9px;border-radius:20px;background:#F3F4F8;color:#1B1C1F;padding:11px 12px;font-size:12px;line-height:1.35}
.an-h{display:flex;align-items:center;gap:6px;font-size:10.5px;color:#5F6368;margin-bottom:5px}.an-h i{width:16px;height:16px;border-radius:50%;display:inline-flex;align-items:center;justify-content:center;color:#fff;flex-shrink:0}.an-h i svg{width:10px;height:10px}.an-h em{margin-left:auto;font-style:normal;font-size:12px}
.an-b{display:flex;gap:10px;align-items:center}.an-b>div{flex:1;min-width:0}.an-b p{margin:1px 0 0;color:#444}.an-th{width:36px;height:36px;border-radius:8px;background:#ddd center/cover;flex-shrink:0}
.an-big{margin-top:8px;width:100%;aspect-ratio:2/1;border-radius:12px;background:#ddd center/cover}
.ap{height:100%;display:flex;flex-direction:column;background:#F8F9FA;position:relative}.ap-body{flex:1;padding:4px 12px 0;display:flex;flex-direction:column;gap:9px;overflow:hidden}.ap-body>*{flex-shrink:0}
.ap-title{font-size:19px;font-weight:700;margin:2px 2px 2px}
.sk{background:#fff;border-radius:14px}.sk-stats{height:118px;padding:14px;display:flex;gap:12px;align-items:center}.sk-ring{width:62px;height:62px;border-radius:50%;border:7px solid #E8F2FE;border-top-color:#0574F8;flex-shrink:0}
.sk-l{height:7px;border-radius:4px;background:#EFF0F4;margin:6px 0}.sk-grid{display:grid;grid-template-columns:1fr 1fr;gap:9px}.sk-grid div{height:74px}.sk-exam{height:96px;background:#0574F8;opacity:.9}
.ap-nav{height:52px;background:#fff;display:flex;justify-content:space-around;align-items:center;padding-bottom:6px}.ap-nav i{width:18px;height:18px;border-radius:5px;background:#E3E6EC}.ap-nav i:first-child{background:#0574F8}
.ab{background:#fff;border-radius:14px;padding:13px;position:relative;font-size:12px}.ab-mark{display:block;width:20px;height:3px;border-radius:2px;margin-bottom:8px}
.ab-row{display:flex;gap:10px;align-items:center;padding-right:18px}.ab-th{width:46px;height:46px;border-radius:10px;background:#fff center/contain no-repeat;flex-shrink:0}.ab b{display:block;font-size:13.5px;line-height:1.2}.ab p{margin:4px 0 0;color:#5E5E5E;line-height:1.38}
.ab-chip{display:inline-block;margin-top:9px;padding:5px 9px;border-radius:8px;font-size:11px;font-weight:600}
.ax{position:absolute;top:8px;right:8px;width:20px;height:20px;border-radius:50%;background:#F4F6FA;color:#A1A6B7;font-size:10px;display:flex;align-items:center;justify-content:center}
.aimg{position:relative;border-radius:14px;overflow:hidden;background:#F4F6FA}.aimg img{display:block;width:100%;height:auto}.aimg .ax{background:rgba(15,23,42,.6);color:#fff}
.ov{position:absolute;inset:0;background:rgba(10,12,18,.45);display:flex;align-items:center;justify-content:center;padding:16px}
.aw{background:#fff;border-radius:20px;width:100%;overflow:hidden;position:relative;font-size:12px;max-height:100%;overflow-y:auto}.aw .im{width:100%;aspect-ratio:16/9;background:#fff center/contain no-repeat}.aw .im.cover{aspect-ratio:4/3}
.aw .in2{padding:16px}.aw .ic2{width:46px;height:46px;border-radius:12px;background:#fff center/contain no-repeat;margin-bottom:10px}.aw b{display:block;font-size:16px;line-height:1.25;letter-spacing:-.2px;padding-right:18px}.aw p{margin:6px 0 0;color:rgba(18,18,18,.68);line-height:1.5;white-space:pre-wrap;overflow-wrap:anywhere}
.aw .bt{margin-top:14px;border-radius:12px;padding:10px;text-align:center;font-weight:600;font-size:12.5px}.aw .bt2{text-align:center;padding:9px 0 0;color:#0574F8;font-weight:600;font-size:12px}.aw img{display:block;width:100%}
.aw.only .ax{background:rgba(15,23,42,.6);color:#fff}
.al{background:#fff;border-radius:14px;height:44px;display:flex;align-items:center;gap:9px;padding:0 10px;font-size:12.5px;font-weight:600}.al i{width:28px;height:28px;border-radius:50%;background:#E8F2FE;position:relative;flex-shrink:0;display:flex;align-items:center;justify-content:center;color:#0574F8}
.al i svg{width:15px;height:15px}.al i:after{content:'';position:absolute;top:1px;right:1px;width:7px;height:7px;border-radius:50%;background:#ED4621;border:1.5px solid #fff}.al span{flex:1}.al em{font-style:normal;color:#A1A6B7}
.ib-h{display:flex;align-items:center;gap:10px;padding:2px 14px 10px;font-size:17px;font-weight:700}.ib-h i{width:30px;height:30px;border-radius:50%;background:#fff;display:flex;align-items:center;justify-content:center;color:#121212;font-style:normal;font-size:14px}
.ib-l{padding:0 12px;display:flex;flex-direction:column;gap:8px}.ic{background:#fff;border-radius:14px;padding:12px;display:flex;gap:10px;font-size:12px}.ic.old{opacity:.45}
.ic .ci{width:30px;height:30px;border-radius:50%;flex-shrink:0;display:flex;align-items:center;justify-content:center}.ic .ci svg{width:16px;height:16px}.ic .cc{flex:1;min-width:0}.ic .ct{display:flex;gap:6px;align-items:flex-start}.ic .ct b{flex:1;font-size:12.5px;line-height:1.3;overflow-wrap:anywhere}.ic .dot{width:7px;height:7px;border-radius:50%;background:#ED4621;flex-shrink:0;margin-top:4px}
.ic p{margin:3px 0 0;color:rgba(18,18,18,.75);line-height:1.4;overflow-wrap:anywhere}.ic .ci-img{margin-top:7px;border-radius:10px;width:100%;display:block}.ic .cf{display:flex;justify-content:space-between;margin-top:7px;font-size:10.5px;color:#A1A6B7}.ic .cf span{color:#0574F8;font-weight:600;font-size:11.5px}
.nf-hist-h{display:flex;align-items:center;justify-content:space-between;margin-bottom:6px}.nf-hist-h h3{margin:0;font-size:16px}
.nf-msg{display:grid;grid-template-columns:52px minmax(0,1.6fr) minmax(0,1fr) 140px auto;gap:14px;align-items:center;padding:14px 0;border-top:1px solid var(--nf-line)}.nf-msg:first-of-type{border-top:0}
.nf-thumb{width:52px;height:52px;flex-shrink:0;border-radius:12px;background:var(--nf-soft) center/cover no-repeat;display:flex;align-items:center;justify-content:center;color:#A3AAB6}.nf-thumb svg{width:36px;height:26px}
.nf-msg strong{display:block;font-size:14px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.nf-msg small{display:block;font-size:12px;color:var(--text-muted);margin-top:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.nf-msg .nf-expiry small{white-space:normal;overflow:visible;font-variant-numeric:tabular-nums}.nf-expiry{margin-top:7px}
.nf-tags{display:flex;gap:4px;flex-wrap:wrap;margin-top:6px}.nf-tag{display:inline-flex;align-items:center;gap:4px;font-size:11px;font-weight:600;padding:3px 7px;border-radius:6px;background:var(--nf-soft);color:#4A5262}.nf-tag svg{width:12px;height:12px}
.nf-tag.ok{background:var(--success-subtle);color:var(--success)}.nf-tag.bad{background:var(--danger-subtle);color:var(--danger)}.nf-tag.test{background:#FFF4DE;color:#9A5B00}.nf-tag.wait{background:var(--primary-subtle);color:var(--primary)}
.nf-stat{font-size:13px;font-weight:650;font-variant-numeric:tabular-nums;display:flex;gap:12px}.nf-stat span{display:inline-flex;align-items:center;gap:4px}.nf-stat svg{width:14px;height:14px;color:#A3AAB6}.nf-stat+small{margin-top:3px}
.nf-acts{display:flex;gap:4px;justify-content:flex-end}.nf-ib{border:0;background:var(--nf-soft);color:#4A5262;border-radius:10px;height:34px;min-width:34px;padding:0 10px;font:inherit;font-size:12px;font-weight:600;cursor:pointer;display:inline-flex;align-items:center;justify-content:center;gap:5px}
.nf-ib:hover{background:#E9EDF2}.nf-ib.primary{background:var(--primary);color:#fff}.nf-ib.danger:hover{background:var(--danger-subtle);color:var(--danger)}.nf-ib svg{width:15px;height:15px}.nf-ib:disabled{opacity:.5}
.nf-empty{padding:28px;text-align:center;color:var(--text-muted);font-size:13px}
.nf-modal{border:0;border-radius:20px;padding:24px;width:min(400px,92vw);color:var(--text);margin:auto;inset:0;position:fixed;box-shadow:0 24px 60px -20px rgba(16,24,40,.35)}.nf-modal::backdrop{background:rgba(16,24,40,.4)}.nf-modal h3{margin:0 0 14px;font-size:17px}
.nf-sum{display:flex;gap:12px;align-items:center;background:var(--nf-soft);border-radius:14px;padding:12px;margin-bottom:12px}.nf-sum .nf-thumb{background-color:#fff}.nf-sum b{display:block;font-size:14px;overflow-wrap:anywhere}.nf-sum small{display:block;font-size:12px;color:var(--text-muted);margin-top:2px;overflow:hidden;display:-webkit-box;-webkit-box-orient:vertical;-webkit-line-clamp:2}
.nf-modal .nf-tags{margin:0 0 18px}.nf-modal .nf-actions{display:flex;gap:8px;justify-content:flex-end}
#notifications-view .nf-modal input{width:100%;box-sizing:border-box;border:1.5px solid var(--nf-line);border-radius:12px;padding:11px 14px;font:inherit;font-size:14px;margin-bottom:16px}
@media(max-width:1180px){.nf-grid{grid-template-columns:minmax(0,1fr)}.nf-preview{position:static}.nf-msg{grid-template-columns:52px minmax(0,1fr) auto}.nf-msg>.nf-who,.nf-msg>.nf-metric{grid-column:2}.nf-msg>.nf-acts{grid-column:1/-1;justify-content:flex-start}}
@media(max-width:600px){#notifications-view .nf-card{padding:18px}.nf-two,.nf-row{grid-template-columns:minmax(0,1fr)}.nf-tile{padding:12px 4px 10px}.nf-tile svg{width:44px;height:32px}.nf-bar .nf-grow{display:none}.nf-bar #nt-publish{width:100%;justify-content:center;order:5}}
</style>
<div id="nt-page-error" class="nt-error" role="alert"></div>
<div class="nf-grid">
<form id="nt-form" class="nf-card" novalidate>
<section class="nf-sec"><h4>Где увидят</h4>
<label class="nf-push" id="nt-push-tile"><input type="checkbox" id="nt-push">${ART.push}<span><b>Пуш на телефон</b><small id="nt-push-state">iOS и Android</small></span><i></i></label>
<div class="nf-tiles" id="nt-places">${tile('news', 'В списке')}${tile('popup', 'Окно')}${tile('banner', 'Баннер')}</div>
<p class="nf-note" id="nt-place-note"></p>
</section>
<section class="nf-sec"><h4>Содержимое</h4>
<div class="nf-drop" id="nt-drop" tabindex="0" role="button" aria-label="Картинка"></div>
<input type="file" id="nt-file" accept="image/jpeg,image/png,image/webp,image/gif" hidden>
<div class="nf-seg" id="nt-layout-wrap" hidden><label title="Картинка сверху"><input type="radio" name="nt-layout" value="standard" checked>${LAYOUT_ART.standard}Сверху</label><label title="Крупная обложка"><input type="radio" name="nt-layout" value="cover">${LAYOUT_ART.cover}Обложка</label><label title="Маленький значок"><input type="radio" name="nt-layout" value="compact">${LAYOUT_ART.compact}Значок</label></div>
<div class="nf-in"><input id="nt-title" maxlength="80" placeholder="Заголовок" autocomplete="off"><span class="nf-count" id="nt-title-count"></span></div>
<div class="nf-in"><textarea id="nt-body" maxlength="1000" placeholder="Текст"></textarea><span class="nf-count" id="nt-body-count"></span></div>
</section>
<section class="nf-sec"><h4>По нажатию</h4>
<div class="nf-row"><select id="nt-action" aria-label="Действие"><option value="none">Ничего</option><option value="url">Открыть ссылку</option><option value="tickets">Билеты</option><option value="topics">Темы</option><option value="game">Игра</option><option value="feed">Лента</option><option value="settings">Настройки</option><option value="premium">Премиум</option></select><input type="url" id="nt-url" placeholder="https://…" aria-label="Ссылка" hidden></div>
<div class="nf-row" id="nt-button-wrap"><input id="nt-button" maxlength="24" placeholder="Текст кнопки" aria-label="Текст кнопки"><input id="nt-dismiss" maxlength="24" placeholder="Вторая кнопка" aria-label="Вторая кнопка"></div>
<div class="nf-swatches" id="nt-swatches"><button type="button" class="nf-swatch" data-color="" style="background:#0574F8" title="Как в приложении"></button><button type="button" class="nf-swatch" data-color="#16A34A" style="background:#16A34A"></button><button type="button" class="nf-swatch" data-color="#F59E0B" style="background:#F59E0B"></button><button type="button" class="nf-swatch" data-color="#DC2626" style="background:#DC2626"></button><button type="button" class="nf-swatch" data-color="#7C3AED" style="background:#7C3AED"></button><button type="button" class="nf-swatch" data-color="#121212" style="background:#121212"></button><input type="color" id="nt-accent" value="#0574F8" title="Свой цвет"></div>
</section>
<section class="nf-sec nf-two">
<div><h4>Кому</h4><div class="nf-chips" id="nt-platforms">${chip('nt-platform', 'ios', 'iOS', 'checkbox')}${chip('nt-platform', 'android', 'Android', 'checkbox')}${chip('nt-platform', 'web', 'Веб', 'checkbox')}</div>
<div class="nf-chips" id="nt-stores" hidden>${chip('nt-store', 'all', 'Все магазины')}${chip('nt-store', 'play', 'Google Play')}${chip('nt-store', 'rustore', 'RuStore')}</div></div>
<div><h4>Когда</h4><div class="nf-chips">${chip('nt-when', 'now', 'Сразу')}${chip('nt-when', 'later', 'Запланировать')}</div>
<div class="nf-when" id="nt-when-wrap" hidden><input type="datetime-local" id="nt-start" aria-label="Время старта"></div>
<h4 style="margin-top:16px" id="nt-days-label">Показывать</h4><div class="nf-chips">${chip('nt-days', '1', '1 день')}${chip('nt-days', '3', '3 дня')}${chip('nt-days', '7', '7 дней')}${chip('nt-days', '30', '30 дней')}${chip('nt-days', 'forever', 'Постоянно')}</div><p class="nf-note" id="nt-lifetime-note"></p></div>
</section>
<div id="nt-editor-error" class="nt-error" role="alert"></div>
<div class="nf-bar">
<button type="button" class="nf-btn" id="nt-test"><svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="6" y="2" width="12" height="20" rx="3"/><path d="M11 18h2"/></svg>Отправить себе</button>
<div class="nf-recips" id="nt-recips" aria-label="Кому отправить проверку"></div>
<span class="nf-grow"></span>
<button type="button" class="nf-btn ghost" id="nt-reset">Очистить</button>
<button type="submit" class="nf-btn primary" id="nt-publish">Отправить всем</button>
</div>
<p class="nf-result" id="nt-result" role="status"></p>
</form>
<aside class="nf-card nf-preview" aria-label="Предпросмотр">
<div class="nf-tabs" id="nt-tabs"><button type="button" data-tab="push">Пуш</button><button type="button" data-tab="home">Главная</button><button type="button" data-tab="inbox">Уведомления</button></div>
<div class="nf-os" id="nt-os"><button type="button" data-os="ios">iPhone</button><button type="button" data-os="android">Android</button></div>
<div class="nf-phone"><div class="nf-screen" id="nt-screen"></div></div>
</aside>
</div>
<div class="nf-card" style="margin-bottom:16px"><div class="nf-hist-h"><h3>Отправленные</h3><button class="nf-ib" id="nt-refresh" title="Обновить"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 12a9 9 0 1 1-3-6.7L21 8M21 3v5h-5"/></svg></button></div><div id="nt-history"><div class="nf-empty">Загрузка…</div></div></div>
<dialog class="nf-modal" id="nt-confirm"><h3>Отправить всем?</h3><div class="nf-sum" id="nt-confirm-sum"></div><div class="nf-tags" id="nt-confirm-tags"></div><div class="nf-actions"><button type="button" class="nf-btn ghost" id="nt-confirm-cancel">Отмена</button><button type="button" class="nf-btn primary" id="nt-confirm-send">Отправить</button></div></dialog>
<dialog class="nf-modal" id="nt-me-dialog"><h3>Аккаунт для проверки</h3><input id="nt-target" list="nt-users-list" maxlength="120" placeholder="email или ID" autocomplete="off"><datalist id="nt-users-list"></datalist><div class="nf-actions"><button type="button" class="nf-btn ghost" id="nt-me-cancel">Отмена</button><button type="button" class="nf-btn primary" id="nt-me-save">Добавить</button></div></dialog>
</div>`;

export const NOTIFICATIONS_CLIENT_JS = String.raw`
VIEW_TITLES.notifications = 'Уведомления';
(function(){
var el=function(id){return document.getElementById('nt-'+id);};
var esc=function(v){return adminEsc(v==null?'':String(v));};
var ART=${JSON.stringify(ART)};
var cfg=null,ready=false,busy=false,items=[],usersLoaded=false,pending=null,afterTarget=null;
var S={push:false,place:'news',layout:'standard',accent:'',platforms:['ios','android','web'],store:'all',when:'now',days:'7',image:'',imgW:0,imgH:0,tab:'',os:'ios'};
// Lock-screen budget: about one line of title on both systems, four lines of
// text on iPhone and one on collapsed Android. FCM rejects more than 4 KB.
var PUSH={title:50,titleSoft:38,body:300,bodySoft:150};
var BODY_MAX={popup:1000,news:1000,banner:200,push:300};
var ACTIONS={none:'',url:'Ссылка',tickets:'Билеты',topics:'Темы',game:'Игра',feed:'Лента',settings:'Настройки',premium:'Премиум'};
var PLACES={news:'В списке',popup:'Окно',banner:'Баннер'};
var PLATFORMS={ios:'iOS',android:'Android',web:'Веб'},ALL=['ios','android','web'];
function platformsOf(m){return m.platform==='all'?ALL:m.platform==='some'?String(m.platforms||'').split(','):[m.platform];}
function has(p){return S.platforms.indexOf(p)>=0;}
function mobile(){return S.platforms.filter(function(p){return p!=='web';});}
var STORES={play:'Google Play',rustore:'RuStore'};
var ICON='https://pdd-drive.ru/assets/icon-192.png',BLUE='#0574F8';
var SVG={eye:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></svg>',
 tap:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M9 11V5a2 2 0 0 1 4 0v6M13 10a2 2 0 0 1 4 0v1a2 2 0 0 1 4 0v4a7 7 0 0 1-7 7h-1a7 7 0 0 1-6-3.4L4 15a2 2 0 0 1 3.4-2.1L9 15"/></svg>',
 copy:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="12" height="12" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></svg>',
 off:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="6" y="5" width="4" height="14" rx="1"/><rect x="14" y="5" width="4" height="14" rx="1"/></svg>',
 on:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>',
 del:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 7h16M10 11v6M14 11v6M6 7l1 13h10l1-13M9 7V4h6v3"/></svg>',
 bell:'<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2"><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9M10 21h4"/></svg>',
 campaign:'<svg viewBox="0 0 24 24" fill="currentColor"><path d="M18 11v2h4v-2h-4zm-2 6.6c1 .7 2.2 1.6 3.2 2.4l1.2-1.6c-1-.7-2.3-1.7-3.2-2.4L16 17.6zM20.4 5.6 19.2 4c-1 .7-2.2 1.7-3.2 2.4L17.2 8c1-.7 2.2-1.7 3.2-2.4zM4 9c-1.1 0-2 .9-2 2v2c0 1.1.9 2 2 2h1v4h2v-4h1l5 3V6L8 9H4zm11.5 3c0-1.3-.6-2.5-1.5-3.4v6.8c.9-.8 1.5-2 1.5-3.4z"/></svg>',
 upload:'<svg width="40" height="40" viewBox="0 0 40 40" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="4" y="7" width="32" height="26" rx="6"/><circle cx="14" cy="16" r="3"/><path d="M6 29l9-8 6 5 5-4 9 7"/></svg>'};
function brand(k){var s=(typeof BRAND_SVGS!=='undefined'&&BRAND_SVGS)||{};return s[k]||'';}
function placeOf(m){return m.kind!=='push'?m.kind:(m.inAppKind||(m.inApp?'popup':'news'));}
function safe(u){return String(u||'').replace(/['"()<>\s\\]/g,'');}
function bg(u){return u?"background-image:url('"+safe(u)+"')":'';}
function https(u){try{return new URL(u).protocol==='https:';}catch(_){return false;}}
function fmt(t,year){return new Date(t).toLocaleString('ru',{timeZone:'Europe/Moscow',day:'numeric',month:'short',year:year?'numeric':undefined,hour:'2-digit',minute:'2-digit'})+' МСК';}
function radio(name){var x=document.querySelector('input[name="'+name+'"]:checked');return x?x.value:'';}
function setRadio(name,v){var x=document.querySelector('input[name="'+name+'"][value="'+v+'"]');if(x)x.checked=true;}
async function api(path,body){var r=await fetch('/api/admin/notifications'+path,{method:body?'POST':'GET',headers:body?{'content-type':'application/json'}:{},body:body?JSON.stringify(body):undefined});var d=await r.json().catch(function(){return {};});if(!r.ok)throw new Error(r.status===401?'Войдите в админку заново':r.status===404&&d.error==='target account not found'?'Аккаунт для проверки не найден':d.error||'Не удалось выполнить запрос');return d;}
// Accounts that get test sends: email or ID, each ticked on or off. Kept in
// this browser; the first single-account version stored one address.
function recipients(){var list=[];try{list=JSON.parse(localStorage.getItem('nt-test-targets')||'null')||[];if(!list.length){var old=localStorage.getItem('nt-test-target');if(old)list=[{v:old,on:true}];}}catch(_){}return list.filter(function(r){return r&&typeof r.v==='string';});}
function saveRecipients(list){try{localStorage.setItem('nt-test-targets',JSON.stringify(list));localStorage.removeItem('nt-test-target');}catch(_){}}
function chosen(){return recipients().filter(function(r){return r.on;}).map(function(r){return r.v;});}
function pushAvailable(){return !!(cfg&&ready&&cfg.pushEnabled)&&(!S.platforms.length||mobile().length>0);}

function draft(){
 var push=S.push,place=S.place,title=el('title').value.trim(),body=el('body').value.trim(),action=el('action').value;
 var imageOnly=!push&&!title&&!body,button=!imageOnly&&(place==='popup'||action!=='none');
 return {kind:push?'push':place,inAppKind:push?place:'',app:'ru',platforms:push?mobile():S.platforms.slice(),store:!push&&has('android')?S.store:'all',
  title:title,body:body,emoji:'',imageUrl:S.image,layout:imageOnly?'image':(place==='popup'&&S.image?S.layout:'standard'),accent:imageOnly?'':S.accent,
  button:button,buttonText:button?el('button').value.trim():'',dismissText:button&&place==='popup'?el('dismiss').value.trim():'',action:action,actionUrl:action==='url'?el('url').value.trim():''};
}
function problem(d){
 if(!cfg)return 'Настройки ещё загружаются';
 if(d.kind==='push'){if(!d.platforms.length)return S.platforms.length?'В вебе пушей нет':'Выберите платформу';if(!pushAvailable())return 'Пуши выключены';if(!d.title&&!d.body)return 'Пушу нужен заголовок или текст';if(d.title.length>PUSH.title)return 'Заголовок пуша — до '+PUSH.title+' символов';}
 else if(!cfg.popupEnabled)return 'Сообщения в приложении выключены';
 else if(!d.platforms.length)return 'Выберите платформу';
 if(!d.title&&!d.body&&!d.imageUrl)return 'Добавьте картинку, заголовок или текст';
 if(d.body.length>BODY_MAX[d.kind==='push'&&S.place==='banner'?'banner':d.kind])return 'Сократите текст';
 if(S.place==='banner'&&d.body.length>200)return 'Текст баннера — до 200 символов';
 if(d.imageUrl&&!https(d.imageUrl))return 'Картинка должна открываться по https://';
 if(d.action==='url'&&!https(d.actionUrl))return 'Укажите ссылку https://';
 if(S.when==='later'){var t=startAt();if(!t)return 'Выберите время старта';if(t<Date.now()-60000)return 'Время старта уже прошло';}
 return '';
}
function startAt(){return S.when==='later'&&el('start').value?new Date(el('start').value).getTime():0;}

// ── Preview: the phone shows the push, the home screen or the inbox.
function tabs(){var t=[];if(S.push)t.push('push');if(S.days!=='forever'&&(S.place!=='news'||!S.push))t.push('home');t.push('inbox');return t;}
function osLabel(){var a=brand('apple'),g=brand('android');el('os').querySelector('[data-os="ios"]').innerHTML=a+'iPhone';el('os').querySelector('[data-os="android"]').innerHTML=g+'Android';}
function status(dark){return '<div class="ph-st"'+(dark?' style="color:#fff"':'')+'><span>9:41</span><i></i><span>●●●</span></div>';}
function lockDate(){return new Date().toLocaleDateString('ru',{weekday:'long',day:'numeric',month:'long'});}
// iPhone (Notification Service Extension): a thumbnail on the right, the picture above the text when expanded.
function pushIos(d){
 var title=d.title||'ПДД 2026',body=d.body,img=d.imageUrl&&https(d.imageUrl);
 var card=function(open){var text='<img class="ic" src="'+ICON+'" alt=""><div class="c"><div class="h"><b class="l1">'+esc(title)+'</b><span>сейчас</span></div>'+(body?'<p class="lc" style="-webkit-line-clamp:'+(open?30:4)+'">'+esc(body)+'</p>':'')+'</div>';
  return open&&img?'<div class="in big"><img class="pic" src="'+esc(d.imageUrl)+'" alt=""><div class="row">'+text+'</div></div>':'<div class="in">'+text+(img?'<span class="th" style="'+bg(d.imageUrl)+'"></span>':'')+'</div>';};
 return '<div class="lk">'+status(true)+'<div class="lk-date">'+esc(lockDate())+'</div><div class="lk-time">9:41</div>'+card(false)+'<div class="lk-cap">Раскрыто</div>'+card(true)+'</div>';
}
function pushAndroid(d){
 var c=d.accent||BLUE,img=d.imageUrl&&https(d.imageUrl),head=function(open){return '<div class="an-h"><i style="background:'+esc(c)+'">'+SVG.bell+'</i><span style="color:'+esc(c)+'">ПДД Россия 2026</span>· сейчас<em>'+(open?'⌃':'⌄')+'</em></div>';};
 var lines=function(open){return (d.title?'<b class="l1">'+esc(d.title)+'</b>':'')+(d.body?'<p class="'+(open&&!img?'lc':'l1')+'"'+(open&&!img?' style="-webkit-line-clamp:8"':'')+'>'+esc(d.body)+'</p>':'');};
 return '<div class="lk an">'+status(true)+'<div class="lk-date">'+esc(lockDate())+'</div><div class="lk-time">9:41</div>'
  +'<div class="an-n">'+head(false)+'<div class="an-b"><div>'+lines(false)+'</div>'+(img?'<span class="an-th" style="'+bg(d.imageUrl)+'"></span>':'')+'</div></div>'
  +'<div class="lk-cap">Раскрыто</div><div class="an-n">'+head(true)+lines(true)+(img?'<div class="an-big" style="'+bg(d.imageUrl)+'"></div>':'')+'</div></div>';
}
function bannerHtml(d){
 var img=d.imageUrl&&https(d.imageUrl),c=d.accent||BLUE;
 if(d.layout==='image')return img?'<div class="aimg"><img src="'+esc(d.imageUrl)+'" alt=""><span class="ax">✕</span></div>':'';
 var chipText=d.buttonText||'Подробнее';
 return '<div class="ab"><span class="ab-mark" style="background:'+esc(c)+'"></span><div class="ab-row">'+(img?'<span class="ab-th" style="'+bg(d.imageUrl)+'"></span>':'')+'<div style="min-width:0">'+(d.title?'<b>'+esc(d.title)+'</b>':'')+(d.body?'<p>'+esc(d.body)+'</p>':'')+'</div></div>'+(d.button?'<span class="ab-chip" style="color:'+esc(c)+';background:'+esc(c)+'14">'+esc(chipText)+' →</span>':'')+'<span class="ax">✕</span></div>';
}
function windowHtml(d){
 var img=d.imageUrl&&https(d.imageUrl),c=d.accent||BLUE;
 if(d.layout==='image')return img?'<div class="aw only"><img src="'+esc(d.imageUrl)+'" alt=""><span class="ax">✕</span></div>':'';
 var pic=img&&d.layout!=='compact'?'<div class="im'+(d.layout==='cover'?' cover':'')+'" style="'+bg(d.imageUrl)+'"></div>':'';
 var label=d.buttonText||(d.action==='none'?'Понятно':'Открыть');
 return '<div class="aw">'+pic+'<div class="in2">'+(img&&d.layout==='compact'?'<div class="ic2" style="'+bg(d.imageUrl)+'"></div>':'')+(d.title?'<b>'+esc(d.title)+'</b>':'')+(d.body?'<p>'+esc(d.body)+'</p>':'')
  +(d.button?'<div class="bt" style="background:'+esc(c)+';color:#fff">'+esc(label)+'</div>'+(d.dismissText?'<div class="bt2">'+esc(d.dismissText)+'</div>':''):'')+'</div><span class="ax">✕</span></div>';
}
function home(d){
 var stats='<div class="sk sk-stats"><span class="sk-ring"></span><div style="flex:1"><div class="sk-l" style="width:70%"></div><div class="sk-l" style="width:45%"></div><div class="sk-l" style="width:58%"></div></div></div>';
 var alert=S.place==='news'?'<div class="al"><i>'+SVG.bell+'</i><span>У вас новое уведомление</span><em>✕</em></div>':'';
 var top=S.place==='banner'?(bannerHtml(d)||stats):stats;
 var body='<div class="ap">'+status()+'<div class="ap-body"><div class="ap-title">Обучение</div>'+alert+top+'<div class="sk sk-exam"></div><div class="sk-grid"><div class="sk"></div><div class="sk"></div><div class="sk"></div><div class="sk"></div></div></div><div class="ap-nav"><i></i><i></i><i></i><i></i></div>';
 if(S.place==='popup'){var w=windowHtml(d);if(w)body+='<div class="ov">'+w+'</div>';}
 return body+'</div>';
}
function inbox(d){
 var img=d.imageUrl&&https(d.imageUrl),c=BLUE,title=d.title||(!d.body?'':d.body),body=d.title?d.body:'';
 var action=d.action!=='none'?(d.buttonText||'Открыть'):'';
 var date=new Date(startAt()||Date.now()).toLocaleDateString('ru',{day:'numeric',month:'long',year:'numeric'});
 var card='<div class="ic"><span class="ci" style="background:'+c+'1f;color:'+c+'">'+SVG.campaign+'</span><div class="cc"><div class="ct">'+(title?'<b>'+esc(title)+'</b>':'<b></b>')+'<span class="dot"></span></div>'+(body?'<p>'+esc(body)+'</p>':'')+(img?'<img class="ci-img" src="'+esc(d.imageUrl)+'" alt="">':'')+'<div class="cf">'+esc(date)+(action?'<span>'+esc(action)+'</span>':'')+'</div></div></div>';
 var old='<div class="ic old"><span class="ci" style="background:#2BC2801f;color:#2BC280">'+SVG.bell+'</span><div class="cc"><div class="sk-l" style="width:80%"></div><div class="sk-l" style="width:55%"></div></div></div>';
 return '<div class="ap">'+status()+'<div class="ib-h"><i>←</i>Уведомления</div><div class="ib-l">'+card+old+old+'</div></div>';
}
function renderPreview(){
 var d=draft(),t=tabs();if(t.indexOf(S.tab)<0)S.tab=t[0];
 el('tabs').querySelectorAll('button').forEach(function(b){b.hidden=t.indexOf(b.dataset.tab)<0;b.classList.toggle('on',b.dataset.tab===S.tab);});
 el('os').hidden=S.tab!=='push';el('os').querySelectorAll('button').forEach(function(b){b.classList.toggle('on',b.dataset.os===S.os);});
 if(S.tab==='push')el('screen').innerHTML=S.os==='ios'?pushIos(d):pushAndroid(d);
 else if(S.tab==='home')el('screen').innerHTML=home(d);
 else el('screen').innerHTML=inbox(d);
}

// ── Editor state → controls.
function count(id,n,max,soft){var x=el(id+'-count');x.textContent=n?n+' / '+max:'';x.classList.toggle('warn',!!soft&&n>soft&&n<=max);x.classList.toggle('over',n>max);x.title=soft&&n>soft?'Длиннее — обрежется на экране блокировки':'';}
function sync(){
 var permanent=S.days==='forever';if(permanent){S.push=false;S.place='news';S.tab='inbox';}
 var d=draft(),push=S.push,canPush=pushAvailable(),imageOnly=d.layout==='image';
 el('push').disabled=permanent||(!canPush&&!push);el('push').checked=push;
 document.querySelectorAll('input[name="nt-place"]').forEach(function(x){x.disabled=permanent&&x.value!=='news';});
 el('push-state').textContent=!cfg?'…':!ready?'Firebase не подключён':!cfg.pushEnabled?'Пуши выключены на сервере':!mobile().length&&S.platforms.length?'В вебе недоступен':'iOS и Android';
 setRadio('nt-place',S.place);document.querySelectorAll('input[name="nt-platform"]').forEach(function(x){x.checked=has(x.value);});setRadio('nt-store',S.store);setRadio('nt-when',S.when);setRadio('nt-days',S.days);setRadio('nt-layout',S.layout);
 document.querySelector('input[name="nt-platform"][value="web"]').disabled=push;
 el('place-note').textContent=push&&S.place!=='news'?'Тем, у кого пуши выключены':'';
 el('stores').hidden=push||!has('android');el('when-wrap').hidden=S.when!=='later';
 el('days-label').textContent='Хранить в списке';
 el('lifetime-note').textContent=permanent?'Только в списке, пока вы не выключите или не удалите уведомление.':'По окончании срока исчезнет и из списка. Окно показывается один раз, закрытый баннер не возвращается.';
 var titleMax=push?PUSH.title:80,bodyMax=push?(S.place==='banner'?200:PUSH.body):BODY_MAX[S.place];
 el('title').maxLength=titleMax;el('body').maxLength=bodyMax;
 count('title',el('title').value.trim().length,titleMax,push?PUSH.titleSoft:0);count('body',el('body').value.trim().length,bodyMax,push?PUSH.bodySoft:0);
 el('title').placeholder=push?'Заголовок пуша':'Заголовок';
 el('layout-wrap').hidden=!(S.place==='popup'&&S.image&&!imageOnly);
 el('button-wrap').hidden=!d.button;el('dismiss').hidden=S.place!=='popup';
 el('button').placeholder=S.place==='popup'?(d.action==='none'?'Кнопка: Понятно':'Кнопка: Открыть'):'Кнопка: Подробнее';
 el('url').hidden=d.action!=='url';el('swatches').hidden=imageOnly;
 document.querySelectorAll('#nt-swatches .nf-swatch').forEach(function(s){s.classList.toggle('on',s.dataset.color===S.accent);});
 var drop=el('drop');
 var spec=imageSpec(),size=spec.w+' × '+spec.h,fit=imageFit(spec);
 if(S.image){drop.classList.add('has');drop.innerHTML='<img src="'+esc(S.image)+'" alt=""><div class="nf-grow"><b>'+(S.imgW?S.imgW+' × '+S.imgH:'Картинка')+'</b>'+(fit?'<small class="'+fit.cls+'">'+esc(fit.text)+'</small>':'<small>Нужно '+size+'</small>')+'</div><button type="button" class="nf-link" data-img="replace">Заменить</button><button type="button" class="nf-link danger" data-img="remove">Убрать</button>';}
 else{drop.classList.remove('has');drop.innerHTML=ratioIcon(spec)+'<div class="nf-grow"><b>Картинка '+size+'</b><small>'+esc(['Перетащите или выберите','до 1 МБ',spec.note].filter(Boolean).join(' · '))+'</small></div><button type="button" class="nf-link" data-img="url">Ссылка</button>';}
 el('recips').innerHTML=recipients().map(function(r,i){return '<label class="nf-rc" title="'+esc(r.v)+'"><input type="checkbox" data-rc="'+i+'"'+(r.on?' checked':'')+'><span>'+esc(r.v)+'</span><button type="button" data-rc-del="'+i+'" aria-label="Убрать '+esc(r.v)+'">✕</button></label>';}).join('')+'<button type="button" class="nf-rc-add" id="nt-me">+ Аккаунт</button>';
 var n=chosen().length;el('test').lastChild.textContent=n>1?'Отправить на '+n:'Отправить себе';
 var p=problem(d);
 el('publish').disabled=busy||!!p;el('test').disabled=busy||(!!p&&p!=='Выберите время старта'&&p!=='Время старта уже прошло');
 el('publish').title=el('test').title=p;
 el('publish').textContent=S.when==='later'?'Запланировать':push?'Отправить всем':'Опубликовать';
 renderPreview();saveDraft();
}
function saveDraft(){try{localStorage.setItem('nt-draft',JSON.stringify({s:{push:S.push,place:S.place,layout:S.layout,accent:S.accent,platforms:S.platforms,store:S.store,days:S.days,image:S.image},title:el('title').value,body:el('body').value,action:el('action').value,url:el('url').value,button:el('button').value,dismiss:el('dismiss').value}));}catch(_){}}
function loadDraft(){try{var x=JSON.parse(localStorage.getItem('nt-draft')||'null');if(!x)return;Object.assign(S,x.s||{});if(!Array.isArray(S.platforms))S.platforms=ALL.slice();delete S.platform;['title','body','action','url','button','dismiss'].forEach(function(k){if(typeof x[k]==='string')el(k).value=x[k];});}catch(_){}}
function clearForm(){['title','body','url','button','dismiss','start'].forEach(function(k){el(k).value='';});el('action').value='none';Object.assign(S,{push:false,place:'news',layout:'standard',accent:'',platforms:ALL.slice(),store:'all',when:'now',days:'7',image:'',imgW:0,imgH:0,tab:''});pending=null;el('editor-error').textContent='';}
function fill(m){
 clearForm();S.push=m.kind==='push';S.place=placeOf(m);S.platforms=platformsOf(m).slice();S.store=m.store||'all';S.layout=m.layout==='cover'||m.layout==='compact'?m.layout:'standard';S.accent=m.accent||'';S.image=m.imageUrl||'';
 S.days=m.persistent?'forever':String([1,3,7,30].find(function(days){return days*86400000>=m.expiresAt-(m.startAt||m.createdAt);})||7);
 el('title').value=m.title||'';el('body').value=m.body||'';el('action').value=m.action||'none';el('url').value=m.actionUrl||'';el('button').value=m.buttonText||'';el('dismiss').value=m.dismissText||'';
 el('result').textContent='';sync();el('form').scrollIntoView({behavior:'smooth',block:'start'});
}

// ── Image: the size that fits every place the message appears. In the app a
// picture is always fitted whole, a different shape only adds margins; a push
// crops it: a square from the centre when collapsed, 2:1 on expanded Android.
function imageSpec(){
 var only=!S.push&&!el('title').value.trim()&&!el('body').value.trim();
 if(S.push)return {w:1024,h:512,note:'главное — по центру',crops:true};
 if(S.place==='banner')return only?{w:1920,h:734,note:'правый верхний угол — под крестик'}:{w:512,h:512};
 if(S.place==='popup')return only?{w:1080,h:1350,note:'правый верхний угол — под крестик'}:S.layout==='cover'?{w:1600,h:1200}:S.layout==='compact'?{w:512,h:512}:{w:1600,h:900};
 return {w:1600,h:900};
}
function imageFit(spec){
 if(!S.imgW)return null;
 var off=(S.imgW/S.imgH)/(spec.w/spec.h);
 if(S.imgW<spec.w/2)return {cls:'warn',text:'Маленькая — будет нечёткой, нужно '+spec.w+' × '+spec.h};
 if(Math.abs(off-1)<=0.04)return {cls:'ok',text:'✓ Подходит'};
 var want=spec.w+' × '+spec.h;
 if(spec.crops)return {cls:'warn',text:'В пуше обрежутся края — нужно '+want};
 if(S.place==='banner'&&spec.w===1920)return {cls:'warn',text:(off<1?'Баннер выйдет выше':'Баннер выйдет ниже')+' обычного — лучше '+want};
 return {cls:'warn',text:'Встанет с полями — лучше '+want};
}
function ratioIcon(spec){var k=Math.min(52/spec.w,38/spec.h);return '<span class="nf-ratio"><i style="width:'+Math.round(spec.w*k)+'px;height:'+Math.round(spec.h*k)+'px"></i></span>';}

// ── Image: drop, choose or paste a link.
async function upload(f){
 el('editor-error').textContent='';
 if(!f||['image/jpeg','image/png','image/webp','image/gif'].indexOf(f.type)<0){el('editor-error').textContent='Нужна картинка JPEG, PNG, WebP или GIF';return;}
 if(f.size>1048576){el('editor-error').textContent='Картинка больше 1 МБ — сожмите её';return;}
 el('drop').innerHTML=SVG.upload+'<div class="nf-grow"><b>Загрузка…</b></div>';
 try{var r=await fetch('/api/admin/notifications/image',{method:'POST',headers:{'content-type':f.type},body:f});var d=await r.json();if(!r.ok)throw new Error(d.error||'Не удалось загрузить');setImage(d.url);}
 catch(e){el('editor-error').textContent=e.message;sync();}
}
function setImage(url){S.image=url;S.imgW=S.imgH=0;pending=null;sync();if(!url)return;var probe=new Image();probe.onload=function(){if(S.image===url){S.imgW=probe.naturalWidth;S.imgH=probe.naturalHeight;sync();}};probe.src=url;}
el('drop').addEventListener('click',function(e){var b=e.target.closest('[data-img]');if(b){e.stopPropagation();if(b.dataset.img==='remove')setImage('');else if(b.dataset.img==='replace')el('file').click();else{var u=prompt('Ссылка на картинку (https://)',S.image||'');if(u!==null){u=u.trim();if(u&&!https(u)){el('editor-error').textContent='Картинка должна открываться по https://';return;}setImage(u);}}return;}if(!S.image)el('file').click();});
el('drop').addEventListener('keydown',function(e){if((e.key==='Enter'||e.key===' ')&&!S.image){e.preventDefault();el('file').click();}});
['dragenter','dragover'].forEach(function(t){el('drop').addEventListener(t,function(e){e.preventDefault();el('drop').classList.add('over');});});
['dragleave','drop'].forEach(function(t){el('drop').addEventListener(t,function(e){e.preventDefault();el('drop').classList.remove('over');});});
el('drop').addEventListener('drop',function(e){var f=e.dataTransfer&&e.dataTransfer.files[0];if(f)upload(f);});
el('file').addEventListener('change',function(){var f=el('file').files[0];el('file').value='';if(f)upload(f);});

// ── Controls.
function onFormEdit(e){
 var t=e&&e.target;if(!t)return sync();
 if(t.closest&&t.closest('#nt-recips'))return;
 if(t.id==='nt-push'){S.push=t.checked;S.tab=S.push?'push':'';if(S.push){S.platforms=mobile();if(!S.platforms.length)S.platforms=['ios','android'];}}
 else if(t.name==='nt-place'){S.place=t.value;S.tab=S.place==='news'&&S.push?'inbox':S.place==='news'?'inbox':'home';}
 else if(t.name==='nt-platform'){S.platforms=ALL.filter(function(p){return p===t.value?t.checked:has(p);});if(mobile().length===1)S.os=mobile()[0];}
 else if(t.name==='nt-store')S.store=t.value;
 else if(t.name==='nt-when')S.when=t.value;
 else if(t.name==='nt-days')S.days=t.value;
 else if(t.name==='nt-layout'){S.layout=t.value;S.tab='home';}
 else if(t.id==='nt-accent')S.accent=t.value.toUpperCase();
 else if(t.id==='nt-target')return;
 pending=null;el('result').textContent='';sync();
}
el('form').addEventListener('input',onFormEdit);el('form').addEventListener('change',onFormEdit);
el('swatches').addEventListener('click',function(e){var s=e.target.closest('.nf-swatch');if(!s)return;S.accent=s.dataset.color;sync();});
el('tabs').addEventListener('click',function(e){var b=e.target.closest('[data-tab]');if(b){S.tab=b.dataset.tab;renderPreview();}});
el('os').addEventListener('click',function(e){var b=e.target.closest('[data-os]');if(b){S.os=b.dataset.os;renderPreview();}});
el('reset').onclick=function(){clearForm();el('result').textContent='';sync();};


// ── Sending: a test to my account first, then to everyone.
function prepare(forTest,to){
 var d=draft(),p=problem(d),start=forTest?0:startAt();
 if(p&&!(forTest&&/Время старта|время старта/.test(p))){el('editor-error').textContent=p;return null;}
 return Object.assign(d,{id:crypto.randomUUID(),target:forTest?to:''},start?{startAt:start}:{},{persistent:S.days==='forever',expiresAt:S.days==='forever'?null:(start||Date.now())+Number(S.days)*86400000});
}
async function send(msg,done){
 busy=true;sync();el('editor-error').textContent='';
 try{await api('/publish',msg);done();await load();}
 catch(e){el('editor-error').textContent=e.message;}
 finally{busy=false;sync();}
}
// One test campaign per ticked account: a campaign has a single recipient.
async function sendTest(){
 var to=chosen();if(!to.length){afterTarget=sendTest;openMe();return;}
 var batch=[];for(var i=0;i<to.length;i++){var msg=prepare(true,to[i]);if(!msg)return;batch.push(msg);}
 el('result').textContent='';busy=true;sync();el('editor-error').textContent='';var sent=[],failed=[];
 for(var j=0;j<batch.length;j++){try{await api('/publish',batch[j]);sent.push(batch[j].target);}catch(e){failed.push(batch[j].target+': '+e.message);}}
 busy=false;await load();
 if(sent.length)el('result').textContent='Отправлено: '+sent.join(', ')+(batch[0].kind==='push'?' — проверьте телефоны':' — откройте приложение');
 if(failed.length)el('editor-error').textContent=failed.join('; ');
 sync();
}
function openMe(){el('target').value='';loadUsers();el('me-dialog').showModal();el('target').focus();}
el('test').onclick=sendTest;
el('recips').addEventListener('click',function(e){var del=e.target.closest('[data-rc-del]');if(del){e.preventDefault();var list=recipients();list.splice(Number(del.dataset.rcDel),1);saveRecipients(list);sync();return;}if(e.target.closest('#nt-me')){afterTarget=null;openMe();}});
el('recips').addEventListener('change',function(e){var box=e.target.closest('[data-rc]');if(!box)return;e.stopPropagation();var list=recipients();list[Number(box.dataset.rc)].on=box.checked;saveRecipients(list);sync();});
el('me-cancel').onclick=function(){afterTarget=null;el('me-dialog').close();};
el('me-save').onclick=function(){var v=el('target').value.trim().toLowerCase();if(!v||/[\s'"<>]/.test(v)){el('target').focus();return;}var list=recipients().filter(function(r){return r.v!==v;});list.push({v:v,on:true});saveRecipients(list);el('me-dialog').close();sync();var next=afterTarget;afterTarget=null;if(next)next();};
el('target').addEventListener('keydown',function(e){if(e.key==='Enter'){e.preventDefault();el('me-save').click();}});
async function loadUsers(){if(usersLoaded)return;usersLoaded=true;try{var r=await fetch('/api/admin/users');if(!r.ok)return;var d=await r.json();el('users-list').innerHTML=(d.users||[]).slice(0,200).map(function(u){return '<option value="'+esc(u.email||u.id)+'">'+esc((u.name||'Пользователь')+' · '+u.id)+'</option>';}).join('');}catch(_){}}
function tagsFor(m){
 var t=[];
 if(m.kind==='push')t.push('<span class="nf-tag">'+SVG.bell+'Пуш</span>');
 var place=placeOf(m);if(m.kind!=='push'||place!=='news')t.push('<span class="nf-tag">'+(m.kind==='push'?'+ ':'')+esc(PLACES[place])+'</span>');
 var ps=platformsOf(m);t.push('<span class="nf-tag">'+(ps.length===3?'Все платформы':ps.map(function(p){return (p==='ios'?brand('apple'):p==='android'?brand('android'):'')+esc(PLATFORMS[p]||p);}).join(' · '))+(STORES[m.store]?' · '+esc(STORES[m.store]):'')+'</span>');
 if(m.persistent)t.push('<span class="nf-tag">Постоянно</span>');
 return t.join('');
}
function thumb(m){var place=placeOf(m);return m.imageUrl?'<span class="nf-thumb" style="'+bg(m.imageUrl)+'"></span>':'<span class="nf-thumb">'+ART[m.kind==='push'?'push':place]+'</span>';}
function heading(m){return m.title||m.body||(m.layout==='image'?(placeOf(m)==='banner'?'Баннер-картинка':placeOf(m)==='popup'?'Окно-картинка':'Картинка'):'Сообщение');}
el('form').addEventListener('submit',function(e){
 e.preventDefault();if(busy||el('publish').disabled)return;
 if(!pending)pending=prepare(false);if(!pending)return;
 var m=pending,start=m.startAt||0;
 el('confirm-sum').innerHTML=thumb(m)+'<div style="min-width:0"><b>'+esc(heading(m))+'</b>'+(m.title&&m.body?'<small>'+esc(m.body)+'</small>':'')+'</div>';
 el('confirm-tags').innerHTML=tagsFor(m)+'<span class="nf-tag wait">'+esc(start?fmt(start):'Сразу')+'</span>'+(m.persistent?'':'<span class="nf-tag">'+esc(S.days)+' дн.</span>')+(m.action!=='none'?'<span class="nf-tag">→ '+esc(ACTIONS[m.action])+'</span>':'');
 el('confirm').querySelector('h3').textContent=start?'Запланировать для всех?':m.kind==='push'?'Отправить пуш всем?':'Опубликовать для всех?';
 el('confirm-send').textContent=m.kind==='push'&&!start?'Отправить':'Подтвердить';
 el('confirm').showModal();
});
el('confirm-cancel').onclick=function(){el('confirm').close();};
el('confirm-send').onclick=function(){if(busy||!pending)return;var m=pending;el('confirm').close();send(m,function(){pending=null;clearForm();el('result').textContent=m.startAt?'Запланировано':m.kind==='push'?'Пуш отправляется':'Опубликовано';});};

// ── History.
function timeLeft(ms){
 if(ms<60000)return Math.ceil(ms/1000)+' с';
 var minutes=Math.ceil(ms/60000),days=Math.floor(minutes/1440),hours=Math.floor(minutes%1440/60),rest=minutes%60;
 return (days?days+' д ': '')+(hours?hours+' ч ':'')+(!days||rest?rest+' мин':'');
}
function lifetimeHtml(m,now){
 if(m.persistent)return '<small>Без срока — до отключения или удаления</small>';
 if(!Number.isFinite(m.expiresAt))return '';
 var date='<time datetime="'+new Date(m.expiresAt).toISOString()+'">'+esc(fmt(m.expiresAt,true))+'</time>';
 if(m.expiresAt<=now)return '<small>Исчезло из приложения: '+date+'</small>';
 return '<small>Исчезнет: '+date+'</small><small>'+(m.enabled?'Осталось: '+esc(timeLeft(m.expiresAt-now)):'Сейчас скрыто')+'</small>';
}
function statusTag(m){
 var now=Date.now(),expired=m.expiresAt<=now,scheduled=(m.startAt||0)>now;
 if(m.kind==='push'){
  var s={queued:[scheduled?'Запланирован '+fmt(m.startAt):'В очереди','wait'],sending:['Отправляется','wait'],accepted:['Отправлен','ok'],failed:['Ошибка','bad'],unknown:['Доставка неизвестна','bad'],expired:['Не отправлен — истёк срок','']}[m.status]||[m.status,''];
  if(!m.enabled&&m.status==='queued')s=['Остановлен',''];
  else if(!m.enabled)s=[s[0]+' · скрыт в приложении',''];
  return '<span class="nf-tag '+s[1]+'">'+esc(s[0])+'</span>';
 }
 if(expired)return '<span class="nf-tag">Срок истёк</span>';
 if(!m.enabled)return '<span class="nf-tag">Выключено</span>';
 if(scheduled)return '<span class="nf-tag wait">С '+esc(fmt(m.startAt))+'</span>';
 return '<span class="nf-tag ok">Показывается</span>';
}
function render(list){
 if(!list.length){el('history').innerHTML='<div class="nf-empty">Здесь появятся отправленные сообщения</div>';return;}
 var now=Date.now();
 el('history').innerHTML=list.map(function(m){
  var expired=m.expiresAt<=now,canToggle=!expired&&(m.kind!=='push'||['queued','accepted','unknown'].indexOf(m.status)>=0||placeOf(m)!=='news');
  var v=Number(m.metrics&&m.metrics.view||0),c=Number(m.metrics&&m.metrics.click||0);
  var who=m.target?'<span class="nf-tag test">Тест</span><small>'+esc(m.target)+'</small>':'<small>Все пользователи</small>';
  return '<div class="nf-msg" data-nt-message="'+m.id+'">'+thumb(m)+'<div style="min-width:0"><strong>'+esc(heading(m))+'</strong><small>'+esc(fmt(m.createdAt))+(ACTIONS[m.action]?' · → '+esc(ACTIONS[m.action]):'')+'</small><div class="nf-tags">'+tagsFor(m)+'<span data-nt-status>'+statusTag(m)+'</span></div><div class="nf-expiry" data-nt-lifetime>'+lifetimeHtml(m,now)+'</div>'+(m.error?'<small style="color:var(--danger)">'+esc(m.error)+'</small>':'')+'</div>'
   +'<div class="nf-who">'+who+'</div>'
   +'<div class="nf-metric" title="Уникальные люди: увидели / нажали. Данные приходят с задержкой до 10 минут."><div class="nf-stat"><span>'+SVG.eye+v+'</span><span>'+SVG.tap+c+'</span></div><small>'+(v?'CTR '+(100*c/v).toFixed(1)+'%':'нет данных')+'</small></div>'
   +'<div class="nf-acts">'+(m.target?'<button class="nf-ib primary" data-nt-promote="'+m.id+'" title="Подставить в форму и отправить всем">Всем</button>':'')
   +'<button class="nf-ib" data-nt-copy="'+m.id+'" title="Копия в форму">'+SVG.copy+'</button>'
   +(canToggle?'<button class="nf-ib" data-nt-toggle="'+m.id+'" data-enabled="'+(!m.enabled)+'" title="'+(m.enabled?(m.kind==='push'&&m.status!=='queued'?'Скрыть в приложении':'Выключить'):'Включить')+'">'+(m.enabled?SVG.off:SVG.on)+'</button>':'')
   +(m.status!=='sending'?'<button class="nf-ib danger" data-nt-delete="'+m.id+'" title="Удалить">'+SVG.del+'</button>':'')+'</div></div>';
 }).join('');
}
function updateHistoryTimes(){
 if(document.hidden||document.getElementById('notifications-view').style.display==='none')return;
 var now=Date.now();
 items.forEach(function(m){
  var row=el('history').querySelector('[data-nt-message="'+m.id+'"]');if(!row)return;
  var lifetime=row.querySelector('[data-nt-lifetime]'),html=lifetimeHtml(m,now);if(lifetime.innerHTML!==html)lifetime.innerHTML=html;
  var status=row.querySelector('[data-nt-status]'),tag=statusTag(m);if(status.innerHTML!==tag)status.innerHTML=tag;
  if(!m.persistent&&m.expiresAt<=now){var toggle=row.querySelector('[data-nt-toggle]');if(toggle)toggle.remove();}
 });
}
setInterval(updateHistoryTimes,1000);
document.addEventListener('visibilitychange',updateHistoryTimes);
el('history').addEventListener('click',async function(e){
 var b=e.target.closest('button');if(!b)return;var id=b.dataset.ntPromote||b.dataset.ntCopy||b.dataset.ntToggle||b.dataset.ntDelete,m=items.find(function(x){return x.id===id;});
 if(b.dataset.ntPromote||b.dataset.ntCopy){if(m){fill(m);if(b.dataset.ntPromote)el('result').textContent='Проверено — нажмите «'+el('publish').textContent+'»';}return;}
 if(b.dataset.ntDelete&&!confirm('Удалить сообщение? В приложении оно пропадёт.'))return;
 b.disabled=true;
 try{if(b.dataset.ntDelete)await api('/delete',{id:id});else await api('/toggle',{id:id,enabled:b.dataset.enabled==='true'});await load();}
 catch(err){el('page-error').textContent=err.message;b.disabled=false;}
});
el('refresh').onclick=load;

async function load(){
 el('page-error').textContent='';
 try{var d=await api('');cfg=d.config;ready=d.pushConfigured;
  items=d.messages||[];render(items);if(S.push&&!pushAvailable()&&!busy)S.push=false;sync();}
 catch(e){el('page-error').textContent=e.message;}
}
document.querySelectorAll('.sidebar-menu .nav-item').forEach(function(btn){btn.addEventListener('click',function(){document.getElementById('notifications-view').style.display=btn.dataset.feature==='notifications'?'block':'none';if(btn.dataset.feature==='notifications')load();});});
osLabel();loadDraft();if(S.image)setImage(S.image);sync();
})();
`;
