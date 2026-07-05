#ifndef WEBUI_H
#define WEBUI_H

#define kWebUIHTML @"\
<!DOCTYPE html><html lang=zh><head>\
<meta charset=UTF-8>\
<meta name=viewport content=\"width=device-width,initial-scale=1,maximum-scale=1,user-scalable=no\">\
<title>AdSkipper</title>\
<style>\
*{margin:0;padding:0;box-sizing:border-box}\
body{font:-apple-system-body;background:#0a0a0f;color:#d0d0d0;min-height:100vh}\
.head{background:#141428;padding:12px 56px 12px 16px;border-bottom:1px solid #252545;display:flex;align-items:center}\
.head h1{font-size:18px;font-weight:800;color:#5ef782;display:flex;align-items:center;gap:6px}\
.head h1::before{content:'\\2714';font-size:20px}\
.stats{display:grid;grid-template-columns:repeat(3,1fr);gap:6px;padding:10px 12px;background:#0e0e1a}\
.sc{background:#141428;border-radius:8px;padding:8px 4px;text-align:center}\
.sc .n{font-size:19px;font-weight:800;color:#5ef782}\
.sc .l{font-size:9px;color:#666;margin-top:1px}\
.tabs{display:flex;background:#141428;border-bottom:2px solid #252545;position:sticky;top:0;z-index:10}\
.tab{flex:1;text-align:center;padding:11px;font-size:14px;font-weight:600;color:#555;border-bottom:2px solid transparent;margin-bottom:-2px}\
.tab.on{color:#5ef782;border-bottom-color:#5ef782}\
.pn{display:none;padding:10px 12px 80px}\
.pn.on{display:block}\
.rc{background:#141428;border-radius:8px;padding:10px;margin-bottom:7px;border:1px solid #202040}\
.rc.off{opacity:.35}\
.rh{display:flex;justify-content:space-between;align-items:center;margin-bottom:5px}\
.rid{font-size:12px;font-weight:700;color:#5ef782;max-width:60%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}\
.rm{font-size:10px;color:#777}\
.ra{display:flex;gap:4px;margin-top:6px}\
.bt{background:#252545;color:#aaa;border:none;border-radius:5px;padding:4px 10px;font-size:11px}\
.bt.dg{background:#402020;color:#f07070}\
.bt.pm{background:#204020;color:#5ef782}\
.tg{width:40px;height:22px;border-radius:11px;border:none;position:relative;transition:.2s;background:#333}\
.tg.on{background:#206030}\
.tg::after{content:'';width:18px;height:18px;border-radius:50%;background:#fff;position:absolute;top:2px;left:2px;transition:.2s}\
.tg.on::after{left:20px}\
.dr{background:#141428;border-radius:8px;padding:8px 10px;margin-bottom:6px;display:flex;align-items:center;border:1px solid #202040}\
.dt{font-size:12px;font-family:Menlo,monospace;flex:1;word-break:break-all;margin-right:6px;color:#ccc;font-size:11px}\
.ar{display:flex;gap:6px;margin-bottom:10px}\
.ar input{flex:1;background:#141428;border:1px solid #252545;border-radius:6px;padding:7px 10px;color:#ccc;font-size:13px;outline:none}\
.ar input:focus{border-color:#5ef782}\
.lc{background:#050510;border-radius:8px;padding:6px;max-height:55vh;overflow-y:auto;font-family:Menlo,monospace;font-size:10px;line-height:1.5}\
.le{border-bottom:1px solid #111;padding:2px 0}\
.lt{color:#555;margin-right:6px}\
.lv.block{color:#f07070}\
.lv.info{color:#5ef782}\
.lv.error{color:#f90}\
.lm{color:#aaa}\
.md{display:none;position:fixed;top:0;left:0;width:100%;height:100%;background:rgba(0,0,0,.75);z-index:200;align-items:center;justify-content:center}\
.md.on{display:flex}\
.mc{background:#141428;border-radius:12px;padding:16px;width:90%;max-width:380px;max-height:80vh;overflow-y:auto}\
.mc h3{color:#5ef782;margin-bottom:10px;font-size:15px}\
.mc label{font-size:11px;color:#777;display:block;margin-top:6px;margin-bottom:3px}\
.mc input,.mc select{width:100%;background:#0a0a0f;border:1px solid #252545;border-radius:6px;padding:7px;color:#ccc;font-size:13px;outline:none;margin-bottom:4px}\
.mc input:focus,.mc select:focus{border-color:#5ef782}\
.ma{display:flex;gap:6px;justify-content:flex-end;margin-top:10px}\
.fab{position:fixed;bottom:16px;right:16px;width:44px;height:44px;border-radius:22px;background:#206030;color:#5ef782;font-size:22px;border:none;box-shadow:0 2px 10px rgba(94,247,130,.25);display:flex;align-items:center;justify-content:center;z-index:50}\
.emp{text-align:center;color:#444;padding:30px;font-size:12px}\
</style></head><body>\
<div class=head><h1>AdSkipper</h1><span style=font-size:10px;color:#555;margin-left:auto>摇晃打开</span></div>\
<div class=stats id=st></div>\
<div class=tabs>\
<div class=\"tab on\" data-t=rules>规则</div>\
<div class=tab data-t=domains>域名</div>\
<div class=tab data-t=logs>日志</div>\
</div>\
<div class=\"pn on\" id=pr></div>\
<div class=pn id=pd></div>\
<div class=pn id=pl><div class=lc id=lb></div></div>\
<button class=fab id=fab onclick=showAdd()>+</button>\
<div class=md id=md><div class=mc id=mc></div></div>\
<script>\
var cbId=0,cbs={},tab='rules';\
function call(action,params){return new Promise(function(resolve){var id=++cbId;cbs[id]=resolve;webkit.messageHandlers.adskipper.postMessage({action:action,params:params||{},cbId:id})})}\
function _cb(id,data){if(cbs[id]){cbs[id](data);delete cbs[id]}}\
document.querySelectorAll('.tab').forEach(function(t){t.onclick=function(){switchTab(t.dataset.t)}});\
function switchTab(t){tab=t;document.querySelectorAll('.tab').forEach(function(x){x.classList.toggle('on',x.dataset.t===t)});document.querySelectorAll('.pn').forEach(function(x){x.classList.remove('on')});document.getElementById('p'+t[0]).classList.add('on');if(t==='logs')loadLogs();document.getElementById('fab').style.display=t==='rules'?'flex':'none'}\
function es(s){return String(s||'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/\"/g,'&quot;').replace(/'/g,'&#39;')}\
function loadRules(){call('getRules').then(function(d){var h='';if(!d.rules||!d.rules.length)h='<div class=emp>暂无规则</div>';else d.rules.forEach(function(r){h+='<div class=\"rc'+(r.enabled?'':' off')+'\"><div class=rh><span class=rid>'+es(r.id)+'</span><button class=\"tg'+(r.enabled?' on':'')+'\" data-id=\"'+es(r.id)+'\" data-on='+(r.enabled?1:0)+'></button></div><div class=rm>'+['类名','关键词','无障碍','SDK'][r.targetType]+' | '+['阻止','移除','点击','关闭','隐藏'][r.actionType]+' | '+es(r.targetValue)+'</div><div class=ra><button class=bt data-edit=\"'+es(r.id)+'\">&nbsp;编辑</button><button class=\"bt dg\" data-del=\"'+es(r.id)+'\">&nbsp;删除</button></div></div>'});document.getElementById('pr').innerHTML=h;bindEvents()})}\
function bindEvents(){document.querySelectorAll('.tg').forEach(function(b){b.onclick=function(e){e.stopPropagation();var id=this.dataset.id;call('toggleRule',{id:id}).then(function(){loadRules()})}});document.querySelectorAll('[data-edit]').forEach(function(b){b.onclick=function(){editRule(this.dataset.edit)}});document.querySelectorAll('[data-del]').forEach(function(b){b.onclick=function(){if(confirm('删除 '+this.dataset.del+'?'))call('deleteRule',{id:this.dataset.del}).then(function(){loadRules()})}})}\
function showAdd(){document.getElementById('mc').innerHTML='<h3>添加规则</h3><label>ID</label><input id=fi placeholder=my_rule><label>目标类型</label><select id=ft><option value=0>类名</option><option value=1>关键词</option><option value=2>无障碍标签</option></select><label>目标值</label><input id=fv placeholder=\"BUSplashAdView\"><label>动作</label><select id=fa><option value=0>阻止</option><option value=1>移除</option><option value=2>点击</option><option value=3>关闭</option><option value=4>隐藏</option></select><label>延迟(秒)</label><input id=fd value=0.3 type=number step=0.1><label>优先级</label><input id=fp value=50 type=number><label>正则</label><select id=fr><option value=0>否</option><option value=1>是</option></select><div class=ma><button class=bt onclick=closeMd()>取消</button><button class=\"bt pm\" onclick=addRule()>保存</button></div>';document.getElementById('md').classList.add('on')}\
function editRule(id){call('getRules').then(function(d){var r=d.rules.find(function(x){return x.id===id});if(!r)return;document.getElementById('mc').innerHTML='<h3>编辑 '+es(id)+'</h3><label>目标类型</label><select id=ft>'+[['类名',0],['关键词',1],['无障碍',2]].map(function(t){return'<option value='+t[1]+(r.targetType===t[1]?' selected':'')+'>'+t[0]+'</option>'}).join('')+'</select><label>目标值</label><input id=fv value=\"'+es(r.targetValue)+'\"><label>动作</label><select id=fa>'+['阻止','移除','点击','关闭','隐藏'].map(function(t,i){return'<option value='+i+(r.actionType===i?' selected':'')+'>'+t+'</option>'}).join('')+'</select><label>延迟</label><input id=fd type=number value=\"'+r.delay+'\" step=0.1><label>优先级</label><input id=fp type=number value='+r.priority+'><label>正则</label><select id=fr><option value=0'+(r.useRegex?'':' selected')+'>否</option><option value=1'+(r.useRegex?' selected':'')+'>是</option></select><div class=ma><button class=bt onclick=closeMd()>取消</button><button class=\"bt pm\" onclick=\"updateRule('+es(id)+')\">保存</button></div>';document.getElementById('md').classList.add('on')})}\
function addRule(){var v=$('fv').value.trim(),i=$('fi').value.trim()||v;if(!v)return;call('saveRule',{id:i,targetType:+$('ft').value,targetValue:v,actionType:+$('fa').value,delay:+($('fd').value||0.3),priority:+($('fp').value||50),enabled:true,useRegex:+$('fr').value===1}).then(function(){closeMd();loadRules()})}\
function updateRule(id){call('saveRule',{id:id,targetType:+$('ft').value,targetValue:$('fv').value.trim(),actionType:+$('fa').value,delay:+($('fd').value||0.3),priority:+($('fp').value||50),enabled:true,useRegex:+$('fr').value===1}).then(function(){closeMd();loadRules()})}\
function closeMd(){document.getElementById('md').classList.remove('on')}\
document.getElementById('md').onclick=function(e){if(e.target===this)closeMd()}\
function loadDomains(){call('getDomains').then(function(d){var h='<div class=ar><input id=di placeholder=\"域名 如 *.abc.com\"><button class=\"bt pm\" onclick=addDm()>添加</button></div>';if(!d.domains||!d.domains.length)h+='<div class=emp>暂无域名</div>';else d.domains.forEach(function(dm){h+='<div class=dr><span class=dt>'+es(dm)+'</span><button class=\"bt dg\" onclick=delDm(this)>删除</button></div>'});document.getElementById('pd').innerHTML=h})}\
function addDm(){var v=$('di').value.trim();if(!v)return;call('addDomain',{domain:v}).then(function(){loadDomains()})}\
function delDm(btn){var d=btn.parentElement.querySelector('.dt').textContent;call('deleteDomain',{domain:d}).then(function(){loadDomains()})}\
function loadLogs(){call('getLogs').then(function(d){var h='',ls=d.logs||[],st=Math.max(0,ls.length-200);for(var i=st;i<ls.length;i++){var l=ls[i];h+='<div class=le><span class=lt>'+es(l.time)+'</span> <span class=\"lv '+es(l.level)+'\">'+es(l.level)+'</span> '+es(l.source)+': '+es(l.message)+'</div>'};document.getElementById('lb').innerHTML=h||'<div class=emp>等待日志...</div>';var box=document.getElementById('lb');box.scrollTop=box.scrollHeight})}\
function loadStats(){call('getStats').then(function(d){document.getElementById('st').innerHTML='<div class=sc><div class=n>'+d.total+'</div><div class=l>拦截</div></div><div class=sc><div class=n>'+d.dnsBlocked+'</div><div class=l>DNS</div></div><div class=sc><div class=n>'+d.httpBlocked+'</div><div class=l>HTTP</div></div><div class=sc><div class=n>'+d.uiBlocked+'</div><div class=l>UI</div></div><div class=sc><div class=n>'+d.rules+'</div><div class=l>规则</div></div><div class=sc><div class=n>'+d.domains+'</div><div class=l>域名</div></div>'})}\
function $(id){return document.getElementById(id)}\
function refresh(){loadRules();loadDomains();loadStats();if(tab==='logs')loadLogs()}\
refresh();setInterval(refresh,2500);\
</script></body></html>"

#endif
