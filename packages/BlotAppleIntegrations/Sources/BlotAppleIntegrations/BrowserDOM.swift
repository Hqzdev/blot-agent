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
      const destination = e => {
        if (e.tagName !== 'A' || !e.href || e.hasAttribute('download') || e.hasAttribute('onclick') ||
            e.hasAttribute('ping') || e.hasAttribute('role') || (e.target || document.querySelector('base[target]')?.target || '_self') !== '_self') return '';
        const url = new URL(e.href, location.href);
        if (url.origin !== location.origin || !['https:','http:'].includes(url.protocol) ||
            /delete|remove|logout|signout|unsubscribe|checkout|purchase|approve|confirm|activate|deactivat|submit|transfer|publish|удал|оплат|отправ|публик/i.test(url.pathname + url.search + ' ' + label(e))) return '';
        return url.href;
      };
      const textField = e => (e.isContentEditable || (['INPUT','TEXTAREA'].includes(e.tagName) && !e.readOnly &&
        ['','text','search','email','url','tel','textarea'].includes(e.type || '')));
      const manualForm = e => e.form && [...e.form.elements].some(field => !['hidden','file'].includes(field.type) && secret(field));
      const ordinaryInput = e => {
        if (!textField(e) || manualForm(e) || e.isContentEditable || e.hasAttribute('oninput') || e.hasAttribute('onchange') ||
            e.closest('[aria-live],[data-autosave],[data-auto-save]')) return false;
        const context = [e.name,e.id,label(e),e.form?.id,e.form?.action].join(' ');
        if (/autosave|auto.save|password|login|sign.in|checkout|payment|billing|код|парол|оплат/i.test(context)) return false;
        return e.type === 'search' || !!e.form?.querySelector('button[type="submit"],input[type="submit"],button:not([type])');
      };
      const describe = e => JSON.stringify({tag:e.tagName,type:e.type || '',label:label(e),href:e.href || '',action:e.form?.action || '',disabled:!!e.disabled,secret:secret(e),navigation:!!destination(e),ordinaryInput:ordinaryInput(e),formRevision});
      const matchingTarget = (id, expected, url) => {
        const e = nodes.get(id);
        if (location.href !== new URL(url).href || !e || !visible(e) || e.disabled || secret(e) || describe(e) !== expected) throw Error('stale_or_manual');
        return e;
      };
      const pointFor = e => {
        const viewport = window.visualViewport;
        const left = viewport?.offsetLeft || 0, top = viewport?.offsetTop || 0;
        const width = viewport?.width || innerWidth, height = viewport?.height || innerHeight;
        const r = e.getBoundingClientRect();
        const x1 = Math.max(r.left,left), y1 = Math.max(r.top,top);
        const x2 = Math.min(r.right,left+width), y2 = Math.min(r.bottom,top+height);
        if (x2 <= x1 || y2 <= y1) throw Error('stale_or_manual');
        const x = (x1+x2)/2, y = (y1+y2)/2;
        if (!e.contains(document.elementFromPoint(x,y))) throw Error('stale_or_manual');
        return {x:(x-left)/width,y:(y-top)/height};
      };
      globalThis.__blot = {
        snapshot() {
          nodes.clear(); snapshot = String(++sequence);
          const elements = [];
          const inViewport = [], outsideViewport = [];
          for (const e of document.querySelectorAll('a[href],button,input,textarea,select,[role="button"],[role="link"],[contenteditable="true"]')) {
            if (!visible(e) || e.type === 'hidden') continue;
            const r = e.getBoundingClientRect();
            const inView = r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth;
            if (inView) {
              inViewport.push(e);
              if (inViewport.length === 100) break;
            } else if (outsideViewport.length < 100) outsideViewport.push(e);
          }
          for (const e of inViewport.concat(outsideViewport).slice(0,100)) {
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
        target(id, kind) {
          const e=nodes.get(id);
          if (!e || !visible(e) || e.disabled || secret(e) || (kind === 'browser_type' && (!textField(e) || manualForm(e)))) throw Error('stale_or_manual');
          return describe(e);
        },
        act(id, expected, url, kind, text, cursorX, cursorY) {
          const e=matchingTarget(id, expected, url);
          const point = pointFor(e);
          if (cursorX >= 0 && (Math.abs(point.x - cursorX) > 0.025 || Math.abs(point.y - cursorY) > 0.025)) throw Error('stale_or_manual');
          if (kind==='browser_click' || kind==='browser_purchase') {
            if (kind==='browser_click' && /^(pay\b|place order\b|confirm purchase\b|buy now\b|оплатить|подтвердить покупку|оформить заказ)/i.test(label(e))) throw Error('purchase_review_required');
            const href = kind === 'browser_click' ? destination(e) : '';
            if (href) location.assign(href);
            else e.click();
          }
          else {
            if (!textField(e) || manualForm(e)) throw Error('manual_field');
            if (e.isContentEditable) { e.textContent=text; }
            else {
              const proto=e.tagName==='TEXTAREA'?HTMLTextAreaElement.prototype:HTMLInputElement.prototype;
              const setter = Object.getOwnPropertyDescriptor(proto,'value').set;
              const previous = e.value;
              setter.call(e,text);
              if (e.value !== text) {
                setter.call(e,previous);
                throw Error('manual_field');
              }
            }
            e.dispatchEvent(new Event('input',{bubbles:true})); e.dispatchEvent(new Event('change',{bubbles:true}));
          }
          return {state:'completed',note:'Inspect the page to verify the website outcome.'};
        },
        pointer(id, expected, url) {
          const e=matchingTarget(id, expected, url);
          e.scrollIntoView({block:'center',inline:'nearest',behavior:'instant'});
          return pointFor(e);
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
    static let target = "return globalThis.__blot.target(element, kind);"
    static let action = "return globalThis.__blot.act(element, expected, url, kind, text, cursorX, cursorY);"
    static let pointer = "return globalThis.__blot.pointer(element, expected, url);"
    static let purchaseReview = "const copy=document.body.cloneNode(true);copy.querySelectorAll('input,textarea,select,[contenteditable],script,style,noscript').forEach(e=>e.remove());return (copy.textContent||'').replace(/\\s+/g,' ').trim();"
    static let scroll = "window.scrollBy({top:(direction==='up'?-1:1)*Math.min(window.innerHeight,1200),behavior:'instant'});return {state:'completed'};"
    static let sensitive = "return globalThis.__blot.sensitive();"
}
