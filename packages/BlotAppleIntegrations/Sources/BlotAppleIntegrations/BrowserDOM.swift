import Foundation

/// Fixed scripts run in an isolated content world. The model never supplies executable JavaScript.
enum BrowserDOM {
    static let bootstrap = #"""
    (() => {
      if (globalThis.__blot) return;
      const nodes = new Map(); let sequence = 0; let snapshot = ''; let formRevision = 0;
      const visible = e => e.isConnected && e.getClientRects().length && getComputedStyle(e).visibility !== 'hidden';
      const secret = e => /password|file|hidden/.test(e.type || '') || /password|one-time-code|cc-|webauthn/.test(e.autocomplete || '') || /password|passcode|otp|one.?time|verification.?code|security.?code|authentication.?code|pin.?code|card.?number|card.?expir|credit.?card|cvc|cvv|парол|код.?подтвержд|номер.?карт|пин.?код|срок.?действ/i.test([e.name,e.id,e.getAttribute('aria-label'),e.getAttribute('placeholder'),e.labels?.[0]?.innerText].join(' '));
      const label = e => {
        let associated='';
        if(e.labels?.[0]) {
          const copy=e.labels[0].cloneNode(true);
          copy.querySelectorAll('input,textarea,[contenteditable],script,style').forEach(n=>n.remove());
          associated=copy.textContent;
        }
        return (e.getAttribute('aria-label') || associated || (!e.isContentEditable && !['INPUT','TEXTAREA'].includes(e.tagName) ? e.innerText : '') || e.getAttribute('placeholder') || e.getAttribute('title') || '').trim().slice(0,256);
      };
      const describe = e => JSON.stringify({tag:e.tagName,type:e.type || '',label:label(e),href:e.href || '',action:e.form?.action || '',disabled:!!e.disabled,secret:secret(e),formRevision});
      globalThis.__blot = {
        snapshot() {
          nodes.clear(); snapshot = String(++sequence);
          const elements = [];
          for (const e of document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"],[contenteditable="true"]')) {
            if (!visible(e) || elements.length >= 100) continue;
            const id = snapshot + ':' + elements.length; nodes.set(id,e);
            elements.push({id,tag:e.tagName.toLowerCase(),type:e.type || '',label:label(e),disabled:!!e.disabled,manual:secret(e)});
          }
          const walker = document.createTreeWalker(document.body || document.documentElement,NodeFilter.SHOW_TEXT);
          let text='', visited=0, node;
          while (text.length<24000 && visited<5000 && (node=walker.nextNode())) {
            visited++; const parent=node.parentElement;
            if (!parent || parent.closest('script,style,noscript,template,input,textarea,[contenteditable="true"]') || !visible(parent)) continue;
            const value=node.textContent.trim(); if (value) text+=value+'\n';
          }
          return {text:text.slice(0,24000),truncated:text.length>=24000 || visited>=5000,elements,untrusted_page_content:true};
        },
        target(id) { const e=nodes.get(id); if (!e || !visible(e) || e.disabled || secret(e)) throw Error('stale_or_manual'); return describe(e); },
        act(id, expected, kind, text) {
          const e=nodes.get(id); if (!e || !visible(e) || e.disabled || secret(e) || describe(e)!==expected) throw Error('stale_or_manual');
          if (kind==='browser_click') { e.click(); }
          else {
            if (e.isContentEditable) { e.textContent=text; }
            else {
              if (!['INPUT','TEXTAREA'].includes(e.tagName) || e.readOnly || !['','text','search','email','url','tel','textarea'].includes(e.type || '')) throw Error('manual_field');
              const proto=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
              Object.getOwnPropertyDescriptor(proto,'value').set.call(e,text);
            }
            e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true}));
          }
          return {state:'completed',note:'Inspect the page to verify the website outcome.'};
        },
        sensitive() { return [...document.querySelectorAll('input,textarea,[contenteditable="true"]')].some(e=>visible(e)&&secret(e)); }
      };
      document.addEventListener('input',()=>{formRevision++;window.webkit.messageHandlers.blotDirty.postMessage(true);},{capture:true});
      document.addEventListener('change',()=>{formRevision++;window.webkit.messageHandlers.blotDirty.postMessage(true);},{capture:true});
      document.addEventListener('submit',()=>{formRevision++;window.webkit.messageHandlers.blotDirty.postMessage(true);},{capture:true});
      document.addEventListener('focusin',e=>{if(secret(e.target))window.webkit.messageHandlers.blotDirty.postMessage({sensitive:true});},{capture:true});
      if ([...document.querySelectorAll('input,textarea')].some(e=>visible(e)&&secret(e))) window.webkit.messageHandlers.blotDirty.postMessage({sensitive:true});
    })();
    """#
    static let snapshot = "return globalThis.__blot.snapshot();"
    static let target = "return globalThis.__blot.target(element);"
    static let action = "return globalThis.__blot.act(element, expected, kind, text);"
    static let scroll = "window.scrollBy({top:(direction==='up'?-1:1)*Math.min(window.innerHeight,1200),behavior:'instant'});return {state:'completed'};"
    static let sensitive = "return globalThis.__blot.sensitive();"
}
