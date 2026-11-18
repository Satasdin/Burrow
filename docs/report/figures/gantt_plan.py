import datetime as dt, html, pathlib, sys
D=lambda m,d: (dt.date(2026,m,d)-dt.date(2026,3,1)).days
SPAN=D(12,1); W=522
px=lambda d: d/SPAN*W
SH=['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
fmt=lambda a: f"{a[1]} {SH[a[0]]}"
lanes=[('Milestones','#0F172A','#0F172A',[('Proposal submitted',(6,10)),('Proposal marked, 37 of 40',(6,15)),('Code into the repository',(9,29)),('Chapter 5 draft and app 0.4',(10,16)),('Sprint II review',(11,5)),('Burrow 1.0 released',(11,10)),('Burrow 1.3.0 and final report',(11,18))],True),
('Proposal','#1D4ED8','#2563EB',[('Topic and supervisor',(3,2),(3,27)),('Literature review',(3,16),(5,22)),('Chapters 1 to 3',(4,13),(6,10))],False),
('Analysis and design','#BE185D','#DB2777',[('Requirements and system analysis',(6,22),(7,31)),('Design of the engine and its parts',(7,13),(9,11)),('Build plan and wireframes',(9,7),(9,28)),('Redesign as Burrow',(11,4),(11,9))],False),
('Build','#0F766E','#0D9488',[('Baseline engine: store and retrieval',(6,22),(8,7)),('Engine parts, one increment at a time',(7,20),(9,25)),('Graph layer',(9,14),(10,12)),('CAMR Personal 0.2 to 0.4',(10,1),(10,16)),('Learning, sleep, coding',(10,13),(10,22)),('Engram restart',(10,23),(11,4)),('Mac app and agents',(11,2),(11,9)),('Burrow',(11,9),(11,10)),('Session context and new look',(11,17),(11,18))],False),
('Evaluation','#C2410C','#EA580C',[('Evaluation harness and data sets',(6,15),(7,24)),('Ablations and on-device profiling',(8,10),(9,28)),('Model sweeps, five machines',(10,1),(10,12)),('RAG, agents, cloud',(10,13),(10,22)),('Ollama suites',(11,3),(11,5)),('Burrow gap runs',(11,10),(11,14))],False),
('Release','#4D7C0F','#65A30D',[('CAMR Personal downloads',(10,1),(10,16)),('Landing page and install',(11,10),(11,12)),('Releases 1.2.0 to 1.3.0',(11,13),(11,18))],False),
('Writing','#334155','#475569',[('Chapter 4 draft',(8,3),(9,11)),('Chapters 5 and 6',(9,28),(10,16)),('Chapters 4 to 6 to the guide',(11,3),(11,5)),('Report rebuilt',(11,10),(11,18)),('Corrections and final report',(11,13),(11,18))],False)]
months=['Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov']
e=html.escape
cells=''.join(f'<div style="border-left:1px solid #E2E8F0;{"border-right:1px solid #E2E8F0;" if i==8 else ""}{"background:#F8FAFC" if i%2==0 else ""}"></div>' for i in range(9))
heads=''.join(f'<div style="font-size:14px;font-weight:700;text-align:center;padding-bottom:6px">{m}</div>' for m in months)
body=''
for name,ink,col,items,ms in lanes:
    body+=f'<div style="display:flex;align-items:center;height:28px;border-top:1px solid #CBD5E1"><div style="width:370px;font-size:14.5px;font-weight:700;color:{ink}">{e(name)}</div></div>'
    for it in items:
        if ms:
            x=px(D(*it[1])); mark=f'<div style="position:absolute;top:6px;left:{x-6:.1f}px;width:12px;height:12px;background:{col};transform:rotate(45deg)"></div>'; dates=fmt(it[1])
        else:
            a,b=D(*it[1]),D(*it[2]); w=max(6,px(b)-px(a)); mark=f'<div style="position:absolute;top:6px;height:12px;border-radius:3px;left:{px(a):.1f}px;width:{w:.1f}px;background:{col}"></div>'; dates=f"{fmt(it[1])} – {fmt(it[2])}"
        body+=f'<div style="display:flex;align-items:center;height:24px"><div style="width:260px;box-sizing:border-box;padding-left:14px;font-size:13.5px;white-space:nowrap">{e(it[0])}</div><div style="width:110px;font-size:12.5px;color:#475569;white-space:nowrap">{dates}</div><div style="width:16px"></div><div style="width:522px;height:24px;position:relative">{mark}</div></div>'
page=f'''<!doctype html><html><head><meta charset="utf-8"><link href="https://fonts.googleapis.com/css2?family=Tinos:wght@400;700&display=swap" rel="stylesheet"><style>body{{margin:0}}</style></head><body>
<div style="width:960px;height:1170px;box-sizing:border-box;padding:24px;background:#fff;font-family:Tinos,'Times New Roman',serif;color:#0F172A;position:relative">
<div style="position:absolute;left:410px;top:24px;width:522px;height:1122px;display:grid;grid-template-columns:repeat(9,minmax(0,1fr))">{cells}</div>
<div style="position:relative;display:flex;flex-direction:column">
<div style="display:flex;align-items:flex-end;height:32px;border-bottom:1.5px solid #0F172A"><div style="width:260px;font-size:14px;font-weight:700;padding-bottom:6px">Workstream and task</div><div style="width:110px;font-size:14px;font-weight:700;padding-bottom:6px">Dates</div><div style="width:16px"></div><div style="width:522px;display:grid;grid-template-columns:repeat(9,minmax(0,1fr))">{heads}</div></div>
{body}<div style="border-top:1.5px solid #0F172A"></div></div></div></body></html>'''
pathlib.Path(sys.argv[1]).write_text(page)
