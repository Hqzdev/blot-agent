class MascotAnimator {
  constructor(motion, audio) {
    this.motion = motion;
    this.audio = audio;
    this.pets = [...document.querySelectorAll('.live-pet')];
    this.breath = document.querySelector('.pet-breath');
    this.shadow = document.querySelector('#sonic-underlay');
  }
  draw(seconds) {
    const phase = (seconds * 1000) % 9600;
    const index = Math.min(this.motion.length - 1, Math.floor(phase / 9600 * this.motion.length));
    const frame = this.motion[index];
    this.pets.forEach(pet => {
      pet.querySelector('.pet-body').setAttribute('d', frame.paths[0]);
      pet.querySelector('.pet-eyes').setAttribute('d', frame.paths[1]);
    });
    const sample = this.audio.frames[Math.min(899, Math.floor(seconds * this.audio.fps))];
    this.breath.style.transform = `scale(${1 + sample.bands[0] * 0.023})`;
    this.shadow.style.opacity = String(0.07 + sample.rms * 0.055);
  }
}

class FilmDirector {
  constructor() {
    this.timeline = gsap.timeline({paused:true});
    this.mascot = new MascotAnimator(window.BLOT_MOTION, window.BLOT_AUDIO);
  }
  enter(selector, at, from = {}, duration = 0.5, to = {}) {
    this.timeline.set(selector, {autoAlpha:0}, 0);
    this.timeline.fromTo(selector, {autoAlpha:0, ...from}, {autoAlpha:1, x:0, y:0, scale:1, rotation:0, duration, ease:'power3.out', immediateRender:false, ...to}, at);
  }
  leave(selector, at, duration = 0.3, to = {}) {
    this.timeline.to(selector, {autoAlpha:0, duration, ease:'power2.in', ...to}, at);
  }
  route(selector, at, duration = 0.6) {
    document.querySelectorAll(selector).forEach((path, index) => {
      const length = path.getTotalLength();
      this.timeline.set(path, {strokeDasharray:length, strokeDashoffset:length}, 0);
      this.timeline.fromTo(path, {strokeDasharray:length, strokeDashoffset:length}, {strokeDashoffset:0, duration, ease:'power2.inOut', immediateRender:false}, at + index * 0.10);
    });
  }
  intro() {
    const tl=this.timeline;
    tl.set('.scene:not(#intro), #request, #cursor, #dark-iris, #paper-wipe, #report-sheet', {autoAlpha:0}, 0);
    tl.fromTo('#one',{yPercent:115},{yPercent:0,duration:.55,ease:'power4.out'},.05);
    tl.fromTo('#task',{yPercent:115},{yPercent:0,duration:.55,ease:'power4.out'},.20);
    this.enter('.intro-eyebrow',.25,{x:-20},.45);
    this.enter('#intro-caption',.65,{y:24},.45);
    this.enter('#peek-r',.3,{x:160,rotation:20,scale:.65},.7,{rotation:-12});
    this.enter('#peek-a',.55,{x:160,rotation:-25,scale:.65},.7,{rotation:14});
    this.enter('#peek-w',.8,{y:140,rotation:25,scale:.65},.7,{rotation:-7});
    tl.to('#peek-r',{y:20,rotation:-7,duration:1.2,ease:'sine.inOut'},1.0);
    tl.to('#peek-a',{y:-20,rotation:6,duration:1.1,ease:'sine.inOut'},1.2);
    tl.to('#peek-w',{x:18,rotation:5,duration:.9,ease:'sine.inOut'},1.3);
    tl.fromTo('.intro-rule',{scaleX:0},{scaleX:1,duration:.7,ease:'power3.out'},.5);
    this.enter('.intro-bottom',.7,{y:15},.45);
    this.leave('#intro',1.96,.4,{scale:1.09,y:-65});
  }
  request() {
    const tl=this.timeline;
    this.enter('#app-scene',2.10,{},.12);
    this.enter('#app-window',2.10,{y:240,scale:.9,rotationX:10,rotationY:-7},.85,{rotationX:0,rotationY:0,transformPerspective:1600});
    this.enter('#request',2.65,{y:110,scale:.96},.55);
    this.enter('#request-part-1',3.00,{},.02);
    tl.fromTo('#request-part-1',{clipPath:'inset(0 100% 0 0)'},{clipPath:'inset(0 0% 0 0)',duration:.40,ease:'steps(19)'},3.00);
    this.enter('#request-part-2',3.4,{},.02);
    tl.fromTo('#request-part-2',{clipPath:'inset(0 100% 0 0)'},{clipPath:'inset(0 0% 0 0)',duration:.42,ease:'steps(23)'},3.40);
    tl.fromTo('#caret',{x:0},{x:360,duration:.4,ease:'none'},3.0);
    tl.set('#caret',{x:0,y:45},3.4);
    tl.to('#caret',{x:420,duration:.42,ease:'none'},3.4);
    tl.to('#caret',{opacity:0,duration:.1},3.9);
    this.enter('#cursor',4.3,{x:170,y:100},.45);
    tl.to('#send-button',{scale:.9,duration:.08,ease:'power1.in'},4.90);
    tl.to('#send-button',{scale:1,duration:.23,ease:'back.out(2)'},4.98);
    this.leave('#cursor',5.07,.2,{x:30,y:15});
    this.leave('.request-tools, #send-button',5.12,.18);
    this.enter('#sent-check',5.2,{},.2);
    tl.to('#request',{y:-355,x:95,scale:.78,duration:.72,ease:'power3.inOut',backgroundColor:'#f4f4f5',borderColor:'#e4e4e7'},5.15);
    this.leave('.welcome',5.18,.25,{y:-20});
    tl.to('#app-window',{scale:.86,y:80,rotationX:5,duration:.65,ease:'power3.inOut'},5.8);
    this.leave('#app-scene',6.0,.4,{y:70});
    this.leave('#request',6.15,.35,{y:-450,scale:.6});
    this.leave('#chapter-task',6.2,.2);
    this.enter('#chapter-team',6.45,{},.2);
  }
  team() {
    const tl=this.timeline;
    this.enter('#team-scene',6.25,{},.05);
    tl.fromTo('.team-title h2',{yPercent:105},{yPercent:0,duration:.55,ease:'power4.out'},6.25);
    this.enter('#coordinator',6.35,{y:-35,scale:.92},.5);
    this.route('.team-route',6.65,.65);
    // beat-grid: specialist landings near 6.82, 7.35 and 7.79 seconds.
    this.enter('#agent-r',6.82,{x:100,y:95,rotation:-7,scale:.88},.6,{rotation:-2});
    this.enter('#agent-a',7.10,{y:110,rotation:3,scale:.88},.6);
    this.enter('#agent-w',7.35,{x:-100,y:95,rotation:7,scale:.88},.6,{rotation:2});
    this.enter('.team-bottom',7.6,{x:-30},.4);
    tl.to('#agent-r',{y:-10,rotation:-1,duration:1.0,ease:'sine.inOut'},7.6);
    tl.to('#agent-w',{y:-14,rotation:1,duration:1.0,ease:'sine.inOut'},7.8);
    this.leave('#team-scene',8.95,.42,{scale:1.1,x:-90});
  }
  work() {
    const tl=this.timeline;
    this.enter('#work-scene',9.12,{},.12);
    this.enter('#research-bay .work-heading',9.20,{x:-60},.45);
    this.enter('#research-bay .work-mascot',9.3,{y:55,rotation:-15},.55,{rotation:4});
    this.enter('.source-1',9.30,{x:220,rotation:7},.55,{rotation:-2});
    this.enter('.source-2',9.50,{x:230,rotation:-6},.55,{rotation:1});
    this.enter('.source-3',9.70,{x:240,rotation:6},.55,{rotation:3});
    this.enter('.source-check',10.05,{scale:.5},.4);
    this.enter('.moving-source',10.4,{y:50},.4);
    tl.to('.moving-source',{x:620,y:-145,rotation:-6,duration:.8,ease:'power2.inOut'},10.7);
    this.leave('.moving-source',11.50,.15);
    // One physical workspace; camera tracks across all three specialists.
    tl.to('#work-world',{x:-1920,duration:.62,ease:'power3.inOut'},11.02);
    this.enter('#comparison',11.30,{x:100,rotationY:-10,scale:.95},.55,{rotationY:0,transformPerspective:1400});
    this.enter('#analysis-bay .work-heading',11.36,{x:40},.42);
    this.enter('#analysis-bay .work-mascot',11.4,{y:40,rotation:12},.5,{rotation:-5});
    this.enter('.comparison-row',11.6,{x:40},.4,{stagger:.13});
    tl.to('.comparison-row:nth-last-child(2) i',{opacity:1,duration:.25},12.1);
    this.enter('.insight-note',11.65,{y:18},.25);
    tl.to('#work-world',{x:-3840,duration:.62,ease:'power3.inOut'},12.92);
    this.enter('#draft',13.12,{x:130,rotation:-5,scale:.92},.6,{rotation:1});
    this.enter('#writing-bay .work-heading',13.2,{x:30},.4);
    this.enter('#writing-bay .work-mascot',13.2,{y:40,rotation:-12},.5,{rotation:6});
    this.enter('.draft-row',13.45,{y:26},.4,{stagger:.16});
    tl.fromTo('.draft-caret',{opacity:1},{opacity:0,duration:.3,repeat:3,yoyo:true,ease:'steps(1)'},13.5);
    this.leave('#work-scene',14.9,.25);
    tl.fromTo('#dark-iris',{autoAlpha:1,scale:0,x:550,y:150},{scale:1.15,x:0,y:0,duration:.72,ease:'power3.inOut',immediateRender:false},14.60);
  }
  handoff() {
    const tl=this.timeline;
    this.enter('#handoff-scene',15.12,{},.08);
    this.enter('.handoff-eyebrow',15.2,{y:12},.4);
    tl.fromTo('.handoff-title h2',{yPercent:105},{yPercent:0,duration:.6,ease:'power4.out'},15.25);
    this.enter('#node-r',15.2,{x:-100,y:45,rotation:-12},.55,{rotation:-5});
    this.enter('#node-a',15.35,{y:60,scale:.85},.55);
    this.enter('#node-w',15.5,{x:100,y:45,rotation:12},.55,{rotation:5});
    this.route('.handoff-path',15.52,.55);
    this.enter('#packet-sources',15.82,{scale:.85},.2);
    // beat-locked: 15.82s strong cue, sources handed to analyst.
    tl.to('#packet-sources',{x:245,duration:.75,ease:'power2.inOut'},15.95);
    this.leave('#packet-sources',16.65,.15,{scale:.8});
    tl.to('#node-a',{scale:1.09,duration:.2,ease:'power2.out'},16.60);
    tl.to('#node-a',{scale:1,duration:.35,ease:'power2.inOut'},16.80);
    this.enter('#packet-insights',16.93,{scale:.85},.2);
    tl.to('#packet-insights',{x:240,duration:.75,ease:'power2.inOut'},17.06);
    this.leave('#packet-insights',17.72,.18,{scale:.8});
    tl.to('#node-w',{scale:1.09,duration:.2,ease:'power2.out'},17.7);
    tl.to('#node-w',{scale:1,duration:.35,ease:'power2.inOut'},17.9);
    this.enter('#shared-context',16.1,{y:20},.4);
    this.route('.handoff-return',17.8,.7);
    tl.to('#brand',{color:'#fafafa',duration:.35},15.2);
    tl.to('#brand .pet-body',{fill:'#fafafa',duration:.35},15.2);
    tl.to('#brand .pet-eyes',{fill:'#18181b',duration:.35},15.2);
    tl.to('#chapter',{color:'#a1a1aa',duration:.35},15.2);
  }
  result() {
    const tl=this.timeline;
    // Transform-only adaptation of the installed card-resize component.
    tl.fromTo('#report-sheet',{autoAlpha:0,scale:.16,x:205,y:200,rotation:8},{autoAlpha:1,scale:.24,x:-390,y:170,rotation:-4,duration:.65,ease:'power3.inOut',immediateRender:false},18.10);
    // beat-locked: the assembled file resolves on the 18.55 strong cue.
    tl.fromTo('#paper-wipe',{autoAlpha:1,clipPath:'circle(0% at 52% 67%)'},{clipPath:'circle(100% at 52% 67%)',duration:.85,ease:'power3.inOut',immediateRender:false},18.55);
    tl.to('#report-sheet',{x:0,y:0,scale:1,rotation:0,duration:.9,ease:'power3.inOut'},18.82);
    this.leave('#handoff-scene',18.75,.3);
    tl.set('#dark-iris',{autoAlpha:0},19.6);
    this.enter('#report-scene',19.25,{},.05);
    this.enter('.report-heading>.mono',19.5,{x:-25},.4);
    // beat-locked: result typography lands at 20.19 seconds.
    tl.fromTo('.report-heading h2',{yPercent:110},{yPercent:0,duration:.65,ease:'power4.out'},19.54);
    this.enter('.report-heading>p',20.0,{y:20},.45);
    this.enter('#ready-message',20.45,{x:-35},.45);
    tl.fromTo('.paper-rule',{scaleX:0},{scaleX:1,duration:.55,ease:'power2.out'},19.5);
    this.enter('.paper-section',19.6,{y:20},.4,{stagger:.2});
    tl.to('#report-sheet',{rotation:.7,y:-8,duration:2.3,ease:'sine.inOut'},20.0);
    this.leave('#chapter-team',19.15,.2);
    this.enter('#chapter-result',19.4,{},.2);
    tl.to('#brand',{color:'#27272a',duration:.3},19.15);
    tl.to('#brand .pet-body',{fill:'#27272a',duration:.3},19.15);
    tl.to('#brand .pet-eyes',{fill:'#fafafa',duration:.3},19.15);
    tl.to('#chapter',{color:'#71717a',duration:.3},19.15);
    this.leave('#report-scene',22.72,.4,{x:-100});
    this.enter('#result-scene',22.9,{},.2);
    this.enter('#result-window',22.9,{y:90,scale:.93},.7);
    tl.to('#report-sheet',{x:120,y:30,scale:.65,rotation:0,duration:.8,ease:'power3.inOut'},22.9);
    this.enter('.result-conversation',23.2,{y:28},.5);
    this.leave('#result-scene',25.25,.55,{x:-1840,rotation:-2});
    this.leave('#report-sheet',25.25,.55,{x:-1720,rotation:-2});
  }
  final() {
    const tl=this.timeline;
    this.enter('#final-scene',25.5,{},.05);
    this.leave('#brand, #chapter',25.5,.25);
    this.enter('#final-orbit-r',25.5,{x:-680,y:220,rotation:-25,scale:1.2},.55,{x:-150,y:0,rotation:-12});
    this.enter('#final-orbit-a',25.6,{x:650,y:130,rotation:25,scale:1.2},.55,{x:155,y:10,rotation:10});
    this.enter('#final-orbit-w',25.65,{x:100,y:420,rotation:-15,scale:1.2},.55,{x:0,y:120,rotation:0});
    tl.to('.final-orbit',{x:0,y:0,scale:.3,opacity:0,duration:.5,ease:'power3.in'},26.1);
    this.enter('#final-mark',26.25,{scale:.55,y:50,rotation:-12},.6,{rotation:0,ease:'back.out(1.25)'});
    this.enter('#final-name',26.45,{y:25},.45);
    tl.fromTo('#final-line .mask:first-child span',{yPercent:110},{yPercent:0,duration:.55,ease:'power4.out'},26.6);
    tl.fromTo('#final-line .mask:last-child span',{yPercent:110},{yPercent:0,duration:.55,ease:'power4.out'},26.78);
    this.enter('#final-cta',27.4,{y:24,scale:.96},.5,{ease:'back.out(1.25)'});
    this.enter('#final-footnote',27.65,{y:12},.4);
  }
  build() {
    this.intro(); this.request(); this.team(); this.work(); this.handoff(); this.result(); this.final();
    const playhead={seconds:0};
    this.timeline.to(playhead,{seconds:30,duration:30,ease:'none',onUpdate:()=>this.mascot.draw(playhead.seconds)},0);
    this.mascot.draw(0);
    window.__timelines['blot-launch']=this.timeline;
    return this.timeline;
  }
}
new FilmDirector().build();
