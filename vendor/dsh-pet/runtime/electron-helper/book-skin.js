// Sprite atlas renderer integrated with dsh-pet's window, drag, throw and placement runtime.
// No model, browser, or client launch action is attached to a click, pat, or drag.
(() => {
  const image = new Image();image.src='./shuniang-atlas.png';
  let instance, face=0, interactionUntil=0, state={allowed:false,reason:'等待保护检查'};
  window.__bookDebug={painted:false,interaction:'idle'};
  const faces={idle:0,blink:1,wave:2,read:3,blocked:4,pat:5};
  const lines={pat:'唔……再摸一下，就再读一页。',read:'把这一页读完，再继续忙吧。',wave:'我在这里，入口也在认真守着。'};
  function say(text){if(!instance)return;instance.bookBubble.textContent=text;instance.bookBubble.style.opacity='1';clearTimeout(instance.bookBubbleTimer);instance.bookBubbleTimer=setTimeout(()=>instance.bookBubble.style.opacity='0',4200);}
  function interact(action){face=faces[action]??0;interactionUntil=performance.now()+2800;window.__bookDebug.interaction=action;say(lines[action]||'我在。');}
  window.petGuard.onPet(interact);
  PetSprite.prototype.switchTo=function(name,once,playbackId){
    this.pending=null;this.anim=name;this.once=once;this.playback=playbackId||null;
    if(!this.bookCanvas){
      instance=this;this.videoA.style.display=this.videoB.style.display='none';
      const c=document.createElement('canvas');c.width=640;c.height=360;c.className='book-canvas';
      c.style.cssText='position:absolute;inset:0;width:100%;height:100%;pointer-events:none';this.stage.append(c);this.bookCanvas=c;
      const b=document.createElement('div');b.style.cssText='position:absolute;bottom:100%;left:22%;width:56%;background:#fff8ebee;color:#66412e;border:1px solid #dcb99a;border-radius:14px;padding:10px;font:13px/1.5 "Microsoft YaHei";box-sizing:border-box;opacity:0;pointer-events:none;transition:opacity .2s';this.stage.append(b);this.bookBubble=b;
      const badge=document.createElement('div');badge.style.cssText='position:absolute;top:96%;left:30%;width:40%;text-align:center;font:12px "Microsoft YaHei";color:#8d5239;pointer-events:none';this.stage.append(badge);this.bookBadge=badge;
      this.hit.setAttribute('aria-label','书娘：单击打招呼，拖动移动，右键查看保护');
      this.hit.addEventListener('contextmenu',e=>{e.preventDefault();e.stopImmediatePropagation();window.petGuard.action('menu');},true);
      this.hit.addEventListener('click',e=>{if(!this.justDragged&&!e.ctrlKey&&!e.metaKey)interact('wave');},true);
      let strokes=0,lastX=null,lastTime=0;
      this.hit.addEventListener('mousemove',e=>{const r=this.hit.getBoundingClientRect();const y=(e.clientY-r.top)/r.height;const now=performance.now();if(y<.42&&!this.dragState.active){if(lastX!==null&&now-lastTime<300)strokes+=Math.min(Math.abs(e.clientX-lastX),12);lastX=e.clientX;lastTime=now;if(strokes>60){strokes=0;interact('pat');}}else{strokes=0;lastX=null;}});
      const ctx=c.getContext('2d');
      const tick=()=>{
        if(!c.isConnected)return;
        if(image.complete&&image.naturalWidth){
          let index=performance.now()<interactionUntil?face:state.allowed?(performance.now()%5300<170?1:0):4;
          if(this.dragState.active)index=2;
          const cw=image.naturalWidth/3,ch=image.naturalHeight/2;
          ctx.clearRect(0,0,640,360);const sway=Math.sin(performance.now()/1050)*1.5;
          ctx.drawImage(image,(index%3)*cw,Math.floor(index/3)*ch,cw,ch,150,10+sway,340,340);
          window.__bookDebug.painted=true;window.__bookDebug.frame=index;
        }
        this.bookBadge.textContent=state.preview?'演示 · 禁止启动':state.allowed?'检查通过':'启动已锁定';
        this.bookTimer=setTimeout(tick,50);
      };tick();
    }
    clearTimeout(this.bookEnd);
    if(playbackId)this.reportPlayback(playbackId,'playing');
    if(once)this.bookEnd=setTimeout(()=>{if(playbackId)this.reportPlayback(playbackId,'ended');this.handleEnded();},2400);
    if(this.pendingSquash){this.pendingSquash=false;interact('wave');}
    // Default configuration has no automatic roaming; upstream drag/throw remains active.
  };
  const oldDispose=PetSprite.prototype.dispose;
  PetSprite.prototype.dispose=function(){clearTimeout(this.bookTimer);clearTimeout(this.bookEnd);clearTimeout(this.bookBubbleTimer);return oldDispose.call(this);};
  setInterval(async()=>{try{const next=await window.petGuard.status();if(state.reason!==next.reason&&instance)say(next.allowed?'检查通过了，等你明确点启动。':'先别急，入口已经锁住了。');state=next;}catch{state={allowed:false,reason:'状态不可用'};}},1000);
})();
