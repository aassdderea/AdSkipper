#ifndef WEBUI_H
#define WEBUI_H

#define kWebUIHTML @"\
<!DOCTYPE html>\
<html lang=\"zh-CN\">\
<head>\
<meta charset=\"UTF-8\">\
<meta name=\"viewport\" content=\"width=device-width,initial-scale=1,maximum-scale=1\">\
<title>AdSkipper</title>\
<style>\
*{margin:0;padding:0;box-sizing:border-box}\
body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#0d0d0d;color:#e0e0e0;min-height:100vh}\
.header{background:#1a1a2e;padding:12px 16px;display:flex;align-items:center;justify-content:space-between;border-bottom:1px solid #2a2a4a}\
.header h1{font-size:17px;font-weight:700;color:#7cff6b}\
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:8px;padding:12px 16px;background:#12121f}\
.stat-card{background:#1a1a2e;border-radius:10px;padding:10px;text-align:center}\
.stat-card .num{font-size:22px;font-weight:800;color:#7cff6b}\
.stat-card .label{font-size:10px;color:#888;margin-top:2px}\
.tabs{display:flex;background:#1a1a2e;border-bottom:2px solid #2a2a4a}\
.tab{flex:1;text-align:center;padding:12px;font-size:14px;font-weight:600;color:#666;cursor:pointer;transition:.2s;border-bottom:2px solid transparent;margin-bottom:-2px}\
.tab.active{color:#7cff6b;border-bottom-color:#7cff6b}\
.panel{display:none;padding:12px 16px 100px}\
.panel.active{display:block}\
.rule-card,.domain-row{background:#1a1a2e;border-radius:10px;padding:12px;margin-bottom:8px;border:1px solid #2a2a4a}\
.rule-card.disabled{opacity:.4}\
.rule-header{display:flex;justify-content:space-between;align-items:center;margin-bottom:6px}\
.rule-id{font-size:12px;font-weight:700;color:#7cff6b}\
.rule-meta{font-size:11px;color:#888}\
.rule-actions{display:flex;gap:6px;margin-top:8px}\
.btn{background:#2a2a4a;color:#ccc;border:none;border-radius:6px;padding:6px 12px;font-size:12px;cursor:pointer;transition:.2s}\
.btn:hover{background:#3a3a5a}\
.btn.danger{background:#4a2020;color:#ff6b6b}\
.btn.danger:hover{background:#5a3030}\
.btn.primary{background:#1a4a2a;color:#7cff6b}\
.btn.primary:hover{background:#2a5a3a}\
.btn.toggle{width:44px;height:26px;border-radius:13px;padding:2px;position:relative;transition:.2s;background:#3a3a3a}\
.btn.toggle.on{background:#2a6a3a}\
.btn.toggle::after{content:'';width:22px;height:22px;border-radius:50%;background:white;position:absolute;top:2px;left:2px;transition:.2s}\
.btn.toggle.on::after{left:20px}\
.domain-row{display:flex;justify-content:space-between;align-items:center}\
.domain-text{font-size:13px;font-family:monospace;word-break:break-all;flex:1;margin-right:8px}\
.add-row{display:flex;gap:8px;margin-bottom:12px}\
.add-row input{flex:1;background:#1a1a2e;border:1px solid #2a2a4a;border-radius:8px;padding:8px 12px;color:#e0e0e0;font-size:13px;outline:none}\
.add-row input:focus{border-color:#7cff6b}\
.log-container{background:#0a0a14;border-radius:10px;padding:8px;max-height:60vh;overflow-y:auto;font-family:monospace;font-size:11px;line-height:1.6}\
.log-entry{border-bottom:1px solid #111;padding:3px 0}\
.log-time{color:#666;margin-right:8px}\
.log-level{font-weight:700;margin-right:8px;text-transform:uppercase}\
.log-level.block{color:#ff6b6b}\
.log-level.info{color:#7cff6b}\
.log-level.error{color:#ff9900}\
.log-msg{color:#ccc}\
.modal-overlay{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.7);z-index:100;justify-content:center;align-items:center}\
.modal-overlay.show{display:flex}\
.modal{background:#1a1a2e;border-radius:14px;padding:20px;width:90%;max-width:400px;max-height:80vh;overflow-y:auto}\
.modal h3{color:#7cff6b;margin-bottom:12px}\
.modal label{font-size:12px;color:#888;display:block;margin-top:8px;margin-bottom:4px}\
.modal input,.modal select{width:100%;background:#0d0d0d;border:1px solid #2a2a4a;border-radius:8px;padding:8px;color:#e0e0e0;font-size:13px;outline:none;margin-bottom:8px}\
.modal input:focus,.modal select:focus{border-color:#7cff6b}\
.modal-actions{display:flex;gap:8px;justify-content:flex-end;margin-top:12px}\
.fab{position:fixed;bottom:20px;right:20px;width:48px;height:48px;border-radius:24px;background:#2a6a3a;color:#7cff6b;font-size:24px;border:none;cursor:pointer;display:flex;align-items:center;justify-content:center;box-shadow:0 4px 12px rgba(124,255,107,.3)}\
.empty{text-align:center;color:#555;padding:40px;font-size:13px}\
</style>\
</head>\
<body>\
<div class=\"header\">\
<h1>AdSkipper 控制台</h1>\
<span style=\"font-size:11px;color:#666\" id=\"portDisplay\"></span>\
</div>\
<div class=\"stats\" id=\"stats\"></div>\
<div class=\"tabs\">\
<div class=\"tab active\" onclick=\"switchTab('rules')\">规则</div>\
<div class=\"tab\" onclick=\"switchTab('domains')\">域名</div>\
<div class=\"tab\" onclick=\"switchTab('logs')\">日志</div>\
</div>\
<div class=\"panel active\" id=\"panel-rules\"></div>\
<div class=\"panel\" id=\"panel-domains\"></div>\
<div class=\"panel\" id=\"panel-logs\"><div class=\"log-container\" id=\"logBox\"></div></div>\
<button class=\"fab\" onclick=\"showAddRule()\">+</button>\
<div class=\"modal-overlay\" id=\"modal\"><div class=\"modal\" id=\"modalContent\"></div></div>\
<script>\
let currentTab='rules';let logCount=0;\
function api(url,opts){return fetch(url,opts||{}).then(r=>r.json())}\
function switchTab(t){currentTab=t;document.querySelectorAll('.tab').forEach((e,i)=>{e.classList.toggle('active',document.querySelectorAll('.tab')[i].textContent===({rules:'规则',domains:'域名',logs:'日志'}[t]))});document.querySelectorAll('.panel').forEach(p=>p.classList.remove('active'));document.getElementById('panel-'+t).classList.add('active');t==='logs'&&loadLogs();document.querySelector('.fab').style.display=t==='rules'?'flex':'none'}\
function loadRules(){api('/api/rules').then(d=>{let h='';if(!d.rules||!d.rules.length)h='<div class=empty>暂无规则，点右下角+添加</div>';else d.rules.forEach(r=>{h+='<div class=\"rule-card'+(r.enabled?'':' disabled')+'\"><div class=rule-header><span class=rule-id>'+esc(r.id)+'</span><button class=\"btn toggle'+(r.enabled?' on':'')+'\" onclick=\"toggleRule(\\''+esc(r.id)+'\\')\"></button></div><div class=rule-meta>类型:'+['类名','关键词','无障碍','SDK'][r.targetType]+' | 动作:'+['阻止','移除','点击','关闭','隐藏'][r.actionType]+' | '+esc(r.targetValue)+'</div><div class=rule-actions><button class=btn onclick=\"editRule(\\''+esc(r.id)+'\\')\">编辑</button><button class=\"btn danger\" onclick=\"deleteRule(\\''+esc(r.id)+'\\')\">删除</button></div></div>'});document.getElementById('panel-rules').innerHTML=h})\
function esc(s){return String(s).replace(/\\\\/g,'\\\\\\\\').replace(/'/g,\"\\\\'\").replace(/\"/g,'\\\\\"')}\
function showAddRule(){document.getElementById('modalContent').innerHTML='<h3>添加规则</h3><label>规则ID</label><input id=rid placeholder=my_rule><label>目标类型</label><select id=rt><option value=0>类名</option><option value=1>关键词</option><option value=2>无障碍标签</option></select><label>目标值</label><input id=rv placeholder=\"例: BUSplashAdView\"><label>动作</label><select id=ra><option value=0>阻止加载</option><option value=1>移除视图</option><option value=2>模拟点击</option><option value=3>关闭页面</option><option value=4>隐藏</option></select><label>延迟(秒)</label><input id=rd type=number value=0.3 step=0.1><label>优先级</label><input id=rp type=number value=50><label>正则匹配</label><select id=rr><option value=0>否</option><option value=1>是</option></select><div class=modal-actions><button class=btn onclick=closeModal()>取消</button><button class=\"btn primary\" onclick=addRule()>保存</button></div></div>';document.getElementById('modal').classList.add('show')}\
function editRule(id){api('/api/rules').then(d=>{let r=d.rules.find(x=>x.id===id);if(!r)return;document.getElementById('modalContent').innerHTML='<h3>编辑 '+esc(id)+'</h3><label>目标类型</label><select id=rt>'+(['类名','关键词','无障碍'].map((t,i)=>'<option value='+i+(r.targetType===i?' selected':'')+'>'+t+'</option>').join(''))+'</select><label>目标值</label><input id=rv value=\"'+esc(r.targetValue)+'\"><label>动作</label><select id=ra>'+['阻止','移除','点击','关闭','隐藏'].map((t,i)=>'<option value='+i+(r.actionType===i?' selected':'')+'>'+t+'</option>').join('')+'</select><label>延迟</label><input id=rd type=number value=\"'+r.delay+'\" step=0.1><label>优先级</label><input id=rp type=number value='+r.priority+'><label>正则</label><select id=rr><option value=0'+(r.useRegex?'':' selected')+'>否</option><option value=1'+(r.useRegex?' selected':'')+'>是</option></select><div class=modal-actions><button class=btn onclick=closeModal()>取消</button><button class=\"btn primary\" onclick=\"updateRule(\\''+esc(id)+'\\')\">保存</button></div>';document.getElementById('modal').classList.add('show')})\
function addRule(){let v=val('rv'),i=val('rid')||v;if(!v)return;fetch('/api/rules',{method:'POST',body:JSON.stringify({id:i,targetType:+val('rt'),targetValue:v,actionType:+val('ra'),delay:+val('rd')||0.3,priority:+val('rp')||50,enabled:true,useRegex:+val('rr')===1})}).then(r=>r.json()).then(d=>{closeModal();loadRules()})}\
function updateRule(id){fetch('/api/rules',{method:'POST',body:JSON.stringify({id:id,targetType:+val('rt'),targetValue:val('rv'),actionType:+val('ra'),delay:+val('rd')||0.3,priority:+val('rp')||50,enabled:true,useRegex:+val('rr')===1})}).then(r=>r.json()).then(d=>{closeModal();loadRules()})}\
function toggleRule(id){fetch('/api/rules/toggle',{method:'POST',body:JSON.stringify({id:id})}).then(r=>r.json()).then(d=>loadRules())}\
function deleteRule(id){if(!confirm('确定删除规则 '+id+'?'))return;fetch('/api/rules/delete',{method:'POST',body:JSON.stringify({id:id})}).then(r=>r.json()).then(d=>loadRules())}\
function loadDomains(){api('/api/domains').then(d=>{let h='<div class=add-row><input id=domainInput placeholder=输入域名，如 *.example.com><button class=\"btn primary\" onclick=addDomain()>添加</button></div>';if(!d.domains||!d.domains.length)h+='<div class=empty>暂无域名</div>';else d.domains.forEach(dm=>{h+='<div class=domain-row><span class=domain-text>'+esc(dm)+'</span><button class=\"btn danger\" onclick=\"delDomain(\\''+esc(dm)+'\\')\">删除</button></div>'});document.getElementById('panel-domains').innerHTML=h})\
function addDomain(){let v=document.getElementById('domainInput').value.trim();if(!v)return;fetch('/api/domains',{method:'POST',body:JSON.stringify({domain:v})}).then(r=>r.json()).then(d=>loadDomains())}\
function delDomain(d){fetch('/api/domains/delete',{method:'POST',body:JSON.stringify({domain:d})}).then(r=>r.json()).then(d=>loadDomains())}\
function loadLogs(){api('/api/logs').then(d=>{let h='';let start=d.logs.length-Math.min(200,d.logs.length);for(let i=start;i<d.logs.length;i++){let l=d.logs[i];h+='<div class=log-entry><span class=log-time>'+esc(l.time)+'</span><span class=\"log-level '+esc(l.level)+'\">'+esc(l.level)+'</span><span class=log-msg>'+esc(l.source)+': '+esc(l.message)+'</span></div>'};document.getElementById('logBox').innerHTML=h||'<div class=empty>等待日志...</div>';document.getElementById('logBox').scrollTop=document.getElementById('logBox').scrollHeight})\
function loadStats(){api('/api/stats').then(d=>{document.getElementById('stats').innerHTML='<div class=stat-card><div class=num>'+d.total+'</div><div class=label>总拦截</div></div><div class=stat-card><div class=num>'+d.dnsBlocked+'</div><div class=label>DNS</div></div><div class=stat-card><div class=num>'+d.httpBlocked+'</div><div class=label>HTTP</div></div><div class=stat-card><div class=num>'+d.uiBlocked+'</div><div class=label>UI</div></div><div class=stat-card><div class=num>'+d.rules+'</div><div class=label>规则</div></div><div class=stat-card><div class=num>'+d.domains+'</div><div class=label>域名</div></div>'})\
function val(id){return document.getElementById(id).value}\
function closeModal(){document.getElementById('modal').classList.remove('show')}\
function refresh(){loadRules();loadDomains();loadStats();if(currentTab==='logs')loadLogs()}\
api('/api/status').then(d=>{document.getElementById('portDisplay').textContent='端口:'+d.port});\
refresh();setInterval(refresh,3000);\
</script></body></html>"

#endif
