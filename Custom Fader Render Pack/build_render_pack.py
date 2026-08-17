from reportlab.lib.pagesizes import landscape, letter
from reportlab.pdfgen import canvas
from reportlab.lib.colors import HexColor, Color
from reportlab.pdfbase.pdfmetrics import stringWidth
from reportlab.lib.utils import ImageReader
import os

ROOT = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(ROOT, "Aurora_Custom_Value_Thumb_Fader_Render_Pack.pdf")
CONCEPT = "/Users/dakota/.codex/generated_images/01a00c67-1a1a-7f62-b255-c3303ae13f72/exec-3d364538-3b05-4efd-9244-740bdeb59622.png"
W, H = landscape(letter)

BG = HexColor("#0B0B0F")
WORK = HexColor("#101013")
PANEL = HexColor("#17171C")
RAISED = HexColor("#252532")
WELL = HexColor("#08080B")
TEXT = HexColor("#F2F2F7")
SECONDARY = HexColor("#A0A0AE")
TERTIARY = HexColor("#737381")
ACCENT = HexColor("#8561FA")
ACCENT_BRIGHT = HexColor("#A17AFF")
FOCUS = HexColor("#8CBFFF")
AMBER = HexColor("#FF9E1F")
UV = HexColor("#9E59FF")
COOL = HexColor("#DDF6FF")


def text(c, x, y, value, size=10, color=TEXT, font="Helvetica", align="left"):
    c.setFillColor(color)
    c.setFont(font, size)
    if align == "center":
        c.drawCentredString(x, y, value)
    elif align == "right":
        c.drawRightString(x, y, value)
    else:
        c.drawString(x, y, value)


def header(c, title, subtitle, page):
    c.setFillColor(BG)
    c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColor(ACCENT)
    c.rect(0, H - 8, W, 8, fill=1, stroke=0)
    text(c, 38, H - 50, title, 23, TEXT, "Helvetica-Bold")
    text(c, 38, H - 70, subtitle, 9.5, SECONDARY)
    text(c, W - 38, 24, f"AURORA  /  OPTION C  /  {page}", 7.5, TERTIARY, "Helvetica-Bold", "right")


def rounded(c, x, y, w, h, r, fill, stroke=None, sw=1):
    c.setFillColor(fill)
    if stroke:
        c.setStrokeColor(stroke)
        c.setLineWidth(sw)
        c.roundRect(x, y, w, h, r, fill=1, stroke=1)
    else:
        c.roundRect(x, y, w, h, r, fill=1, stroke=0)


def fader(c, cx, y, height, value, label, accent, state="value", focused=False, scale=1.0):
    channel_w = 42 * scale
    thumb_w = 64 * scale
    thumb_h = 30 * scale
    track_w = 12 * scale
    rounded(c, cx - channel_w/2, y, channel_w, height, 10*scale, WELL, HexColor("#34343D"), 0.8)

    for i in range(5):
        ty = y + 9*scale + (height - 18*scale) * i/4
        c.setStrokeColor(Color(1,1,1,alpha=0.18 if i in (0,2,4) else 0.10))
        c.setLineWidth(1)
        c.line(cx-channel_w/2+5*scale, ty, cx-track_w/2-4*scale, ty)
        c.line(cx+track_w/2+4*scale, ty, cx+channel_w/2-5*scale, ty)

    thumb_half = thumb_h/2
    travel = height - thumb_h
    val = 0.5 if state == "mixed" else max(0, min(1, value))
    cy = y + thumb_half + val * travel

    if state not in ("mixed", "unavailable"):
        c.setFillColor(Color(accent.red, accent.green, accent.blue, alpha=0.28))
        c.roundRect(cx-track_w/2, y+6*scale, track_w, max(6*scale, cy-y-6*scale), track_w/2, fill=1, stroke=0)
        c.setFillColor(accent)
        c.roundRect(cx-track_w/2+2*scale, y+6*scale, track_w-4*scale, max(4*scale, cy-y-6*scale), (track_w-4*scale)/2, fill=1, stroke=0)

    if state == "unavailable":
        rounded(c, cx-thumb_w/2, y+height/2-thumb_h/2, thumb_w, thumb_h, 8*scale, RAISED, HexColor("#44444D"), 1)
        text(c, cx, y+height/2-3*scale, "N/A", 9*scale, TERTIARY, "Helvetica-Bold", "center")
    elif state == "mixed":
        c.setFillColor(PANEL)
        c.setStrokeColor(HexColor("#EAEAF0"))
        c.setLineWidth(1.5)
        c.roundRect(cx-thumb_w/2, cy-thumb_h/2, thumb_w, thumb_h, 8*scale, fill=1, stroke=1)
        text(c, cx, cy-3*scale, "MIXED", 7.5*scale, TEXT, "Helvetica-Bold", "center")
    else:
        shadow = Color(0,0,0,alpha=.45)
        rounded(c, cx-thumb_w/2+2, cy-thumb_h/2-3, thumb_w, thumb_h, 8*scale, shadow)
        thumb_fill = HexColor("#E9F7FA") if label in ("COOL WHITE", "DIMMER") else (HexColor("#E6A42C") if label == "AMBER" else HexColor("#4E298C"))
        border = FOCUS if focused else Color(1,1,1,alpha=.45)
        rounded(c, cx-thumb_w/2, cy-thumb_h/2, thumb_w, thumb_h, 8*scale, thumb_fill, border, 2 if focused else 1)
        dark_text = label in ("COOL WHITE", "DIMMER", "AMBER")
        text(c, cx, cy+1*scale, f"{round(value*100):d}%", 10*scale, HexColor("#101018") if dark_text else TEXT, "Courier-Bold", "center")
        c.setStrokeColor(Color(0,0,0,alpha=.35) if dark_text else Color(1,1,1,alpha=.4))
        c.setLineWidth(1)
        c.line(cx-9*scale, cy-7*scale, cx+9*scale, cy-7*scale)

    text(c, cx, y+height+14*scale, label, 8.5*scale, TEXT, "Helvetica-Bold", "center")


def note(c, x, y, number, title, body, width=210):
    c.setFillColor(ACCENT)
    c.circle(x+9, y+8, 9, fill=1, stroke=0)
    text(c, x+9, y+5, str(number), 8, TEXT, "Helvetica-Bold", "center")
    text(c, x+25, y+8, title, 10, TEXT, "Helvetica-Bold")
    words = body.split()
    lines, current = [], ""
    for word in words:
        trial = (current + " " + word).strip()
        if stringWidth(trial, "Helvetica", 8.5) > width-25 and current:
            lines.append(current); current = word
        else:
            current = trial
    if current: lines.append(current)
    for i, line in enumerate(lines):
        text(c, x+25, y-6-i*11, line, 8.5, SECONDARY)


c = canvas.Canvas(OUT, pagesize=landscape(letter))
c.setTitle("Aurora Custom Value-Thumb Fader Render Pack")
c.setAuthor("Aurora Lighting / Codex")

# Page 1
header(c, "Custom Value-Thumb Fader", "Selected direction: Option C - large, precise, stage-ready controls", 1)
rounded(c, 38, 58, 716, 426, 14, PANEL, HexColor("#30303A"), 1)
text(c, 66, 452, "PROGRAMMER  /  COLOR EMITTERS", 9, TERTIARY, "Helvetica-Bold")
values = [("DIMMER", .72, ACCENT), ("COOL WHITE", .84, COOL), ("AMBER", .46, AMBER), ("UV", .31, UV)]
for i, (lab, val, col) in enumerate(values):
    fader(c, 172+i*150, 120, 282, val, lab, col, focused=(i==2), scale=1.18)
text(c, 66, 80, "Large thumb  |  value in the hand  |  full-channel target  |  no standard slider chrome", 10, SECONDARY)
c.showPage()

# Page 2
header(c, "Anatomy and Dimensions", "Standard-density measurements for implementation", 2)
rounded(c, 38, 56, 350, 430, 14, PANEL, HexColor("#30303A"), 1)
fader(c, 210, 112, 290, .62, "DIMMER", ACCENT, focused=True, scale=1.35)
c.setStrokeColor(AMBER); c.setLineWidth(1)
c.line(166, 301, 90, 301); c.line(165, 278, 90, 246); c.line(183, 178, 90, 188)
note(c, 410, 421, 1, "64 x 30 pt thumb", "The visible control is also the primary grab target. Rounded rectangle, not a tiny capsule.", 315)
note(c, 410, 344, 2, "Value lives inside", "Monospaced numerals stay stable while dragging. A subtle grip line reinforces affordance.", 315)
note(c, 410, 267, 3, "42 pt recessed channel", "The entire 72 pt control width accepts pointer input. The colored fill remains restrained.", 315)
note(c, 410, 190, 4, "Endpoint-safe travel", "Subtract thumb height from travel so the cap remains fully visible at 0 and 100 percent.", 315)
note(c, 410, 113, 5, "Five quiet major ticks", "Ticks aid relative positioning without turning the control into a meter or ruler.", 315)
c.showPage()

# Page 3
header(c, "Semantic State Matrix", "Every state communicates meaning without relying on color alone", 3)
states = [("VALUE", "value", .72), ("FOCUSED", "value", .72), ("MIXED", "mixed", .5), ("UNAVAILABLE", "unavailable", .5)]
for i, (lab, st, val) in enumerate(states):
    x = 122+i*180
    rounded(c, x-72, 94, 144, 352, 12, PANEL, HexColor("#30303A"), 1)
    fader(c, x, 142, 238, val, lab, ACCENT, state=st, focused=(lab=="FOCUSED"), scale=.95)
    description = {"VALUE":"Bound value and percentage", "FOCUSED":"2 pt visible focus ring", "MIXED":"Never reports a fake 50%", "UNAVAILABLE":"No thumb interaction"}[lab]
    text(c, x, 112, description, 7.5, SECONDARY, "Helvetica", "center")
c.showPage()

# Page 4
header(c, "Interaction Contract", "Pointer precision, keyboard control, and accessibility", 4)
items = [
    ("FULL CHANNEL", "Click or drag anywhere in the 72 pt channel. The visible thumb remains 64 pt wide."),
    ("NO INITIAL JUMP", "A drag beginning on the thumb preserves pointer offset; clicking elsewhere seeks immediately."),
    ("CONTINUOUS UPDATE", "Render from the live binding during interaction. Never wait for presentation refresh or mouse-up."),
    ("FINE CONTROL", "Arrow 1%; Shift-arrow 0.1%; Option-arrow 5%; Home 0%; End 100%."),
    ("ACCESSIBLE", "One adjustable element with full label, semantic value, and a visible keyboard focus ring."),
    ("OVERFLOW", "When emitter count grows, scroll horizontally. Never squeeze controls below the minimum width."),
]
for i, (title, body) in enumerate(items):
    col = i % 2; row = i // 2
    x = 48 + col*370; y = 405-row*112
    rounded(c, x, y-67, 344, 88, 10, PANEL, HexColor("#30303A"), 1)
    text(c, x+18, y-4, title, 10, ACCENT_BRIGHT, "Helvetica-Bold")
    words=body.split(); line=""; lines=[]
    for w in words:
        t=(line+" "+w).strip()
        if stringWidth(t,"Helvetica",9)>305 and line: lines.append(line); line=w
        else: line=t
    if line: lines.append(line)
    for j,l in enumerate(lines): text(c,x+18,y-22-j*12,l,9,SECONDARY)
c.showPage()

# Page 5
header(c, "Original Concept Board", "Option C was selected from the initial three-direction exploration", 5)
if os.path.exists(CONCEPT):
    img = ImageReader(CONCEPT)
    iw, ih = img.getSize(); maxw, maxh = 716, 385
    s = min(maxw/iw, maxh/ih)
    dw, dh = iw*s, ih*s
    c.drawImage(img, (W-dw)/2, 76+(maxh-dh)/2, width=dw, height=dh, preserveAspectRatio=True, mask='auto')
    c.setStrokeColor(HexColor("#30303A")); c.rect((W-dw)/2,76+(maxh-dh)/2,dw,dh,fill=0,stroke=1)
text(c, 38, 54, "Decision: carry forward the Value Thumb geometry; use Aurora tokens and emitter-aware colors.", 9, SECONDARY)
c.showPage()

c.save()
print(OUT)
