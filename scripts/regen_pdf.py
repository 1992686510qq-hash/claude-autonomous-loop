# -*- coding: utf-8 -*-
"""Regenerate PDFs with Chinese font support"""
import os
import glob
import re
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak
from reportlab.lib.units import cm, mm
from reportlab.lib.colors import HexColor, black, grey, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_LEFT, TA_CENTER, TA_JUSTIFY

# Register Chinese fonts
FONT_PATH = "C:/Windows/Fonts"
pdfmetrics.registerFont(TTFont('SimHei', f'{FONT_PATH}/simhei.ttf'))
pdfmetrics.registerFont(TTFont('SimSun', f'{FONT_PATH}/simsun.ttc'))
pdfmetrics.registerFont(TTFont('SimKai', f'{FONT_PATH}/simkai.ttf'))
pdfmetrics.registerFont(TTFont('MsYh', f'{FONT_PATH}/msyh.ttc'))

# Source markdown files
MD_DIR = "D:/Claude Code/scan-project"
PDF_DIR = "D:/Claude Code/scan-project/output/pdf"

MD_FILES = {
    "profile": ("analysis/profile.md", "个人画像"),
    "strengths-weaknesses": ("analysis/strengths-weaknesses.md", "优缺点分析"),
    "timeline": ("analysis/timeline.md", "人生时间线"),
    "knowledge-map": ("analysis/knowledge-map.md", "知识图谱"),
    "learning-pattern": ("analysis/learning-pattern.md", "学习模式"),
    "social-network": ("analysis/social-network.md", "社交网络"),
    "health-habits": ("analysis/health-habits.md", "健康习惯"),
    "cc-review": ("analysis/cc-review.md", "CC使用复盘"),
    "digital-twin": ("output/digital-twin.md", "数字分身"),
    "growth-roadmap": ("output/growth-roadmap.md", "成长路线图"),
    "exam-prep-plan": ("output/exam-prep-plan.md", "考试冲刺方案"),
    "research-roadmap": ("output/research-roadmap.md", "科研路径"),
    "grad-exam-plan": ("output/grad-exam-plan.md", "考研规划"),
    "confusion-answers": ("output/confusion-answers.md", "困惑解答"),
    "emotional-report": ("output/emotional-report.md", "情感分析"),
    "lessons": ("comparisons/lessons.md", "伟人经验教训"),
}

def parse_md(text):
    """Parse markdown into structured elements"""
    lines = text.split('\n')
    elements = []
    current_table = []
    in_table = False
    in_code = False
    code_lines = []

    for line in lines:
        # Code block
        if line.strip().startswith('```'):
            if in_code:
                elements.append(('code', '\n'.join(code_lines)))
                code_lines = []
                in_code = False
            else:
                in_code = True
            continue
        if in_code:
            code_lines.append(line)
            continue

        # Table
        if '|' in line and line.strip().startswith('|'):
            cells = [c.strip() for c in line.strip().strip('|').split('|')]
            # Skip separator rows
            if all(re.match(r'^[-:]+$', c) for c in cells):
                continue
            current_table.append(cells)
            in_table = True
            continue
        elif in_table and current_table:
            elements.append(('table', current_table))
            current_table = []
            in_table = False

        # Headers
        if line.startswith('#'):
            level = len(line) - len(line.lstrip('#'))
            text = line.lstrip('#').strip()
            elements.append(('h' + str(level), text))
            continue

        # Empty line
        if not line.strip():
            elements.append(('blank', ''))
            continue

        # List items
        if line.strip().startswith(('- ', '* ', '• ')):
            text = line.strip()[2:]
            elements.append(('li', text))
            continue

        # Numbered list
        m = re.match(r'^(\d+)[.、）]\s*(.*)', line.strip())
        if m:
            elements.append(('oli', f"{m.group(1)}. {m.group(2)}"))
            continue

        # Normal text
        elements.append(('p', line.strip()))

    if current_table:
        elements.append(('table', current_table))

    return elements

def clean_md_formatting(text):
    """Remove markdown formatting for PDF"""
    text = re.sub(r'\*\*(.*?)\*\*', r'\1', text)
    text = re.sub(r'\*(.*?)\*', r'\1', text)
    text = re.sub(r'`(.*?)`', r'\1', text)
    text = re.sub(r'\[(.*?)\]\(.*?\)', r'\1', text)
    text = text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
    return text

def build_pdf(md_path, pdf_path, title):
    """Convert markdown to PDF with Chinese support"""
    if not os.path.exists(md_path):
        print(f"  SKIP: {md_path} not found")
        return

    with open(md_path, 'r', encoding='utf-8') as f:
        text = f.read()

    elements = parse_md(text)

    doc = SimpleDocTemplate(pdf_path, pagesize=A4,
                           topMargin=2*cm, bottomMargin=2*cm,
                           leftMargin=2*cm, rightMargin=2*cm)

    # Styles
    styles = getSampleStyleSheet()

    title_style = ParagraphStyle('CNTitle', fontName='SimHei', fontSize=22,
                                  leading=28, alignment=TA_CENTER, spaceAfter=20,
                                  textColor=HexColor('#1a1a2e'))

    h1_style = ParagraphStyle('CNH1', fontName='SimHei', fontSize=16,
                               leading=22, spaceBefore=16, spaceAfter=8,
                               textColor=HexColor('#16213e'))

    h2_style = ParagraphStyle('CNH2', fontName='SimHei', fontSize=14,
                               leading=18, spaceBefore=12, spaceAfter=6,
                               textColor=HexColor('#0f3460'))

    h3_style = ParagraphStyle('CNH3', fontName='SimHei', fontSize=12,
                               leading=16, spaceBefore=8, spaceAfter=4,
                               textColor=HexColor('#533483'))

    p_style = ParagraphStyle('CNP', fontName='SimSun', fontSize=10,
                              leading=16, spaceAfter=4, alignment=TA_JUSTIFY)

    li_style = ParagraphStyle('CNLI', fontName='SimSun', fontSize=10,
                               leading=16, leftIndent=20, spaceAfter=2,
                               bulletIndent=10)

    code_style = ParagraphStyle('CNCode', fontName='SimSun', fontSize=9,
                                 leading=13, leftIndent=10, spaceAfter=6,
                                 backColor=HexColor('#f5f5f5'))

    story = []

    # Title page
    story.append(Spacer(1, 3*cm))
    story.append(Paragraph(title, title_style))
    story.append(Spacer(1, 1*cm))
    story.append(Paragraph("个人全量扫描与成长规划", ParagraphStyle('Sub', fontName='MsYh', fontSize=14, alignment=TA_CENTER, textColor=HexColor('#666666'))))
    story.append(Spacer(1, 0.5*cm))
    story.append(Paragraph("2026-05-28 生成", ParagraphStyle('Date', fontName='MsYh', fontSize=10, alignment=TA_CENTER, textColor=HexColor('#999999'))))
    story.append(PageBreak())

    for etype, content in elements:
        if etype == 'h1':
            story.append(Paragraph(clean_md_formatting(content), h1_style))
        elif etype == 'h2':
            story.append(Paragraph(clean_md_formatting(content), h2_style))
        elif etype == 'h3':
            story.append(Paragraph(clean_md_formatting(content), h3_style))
        elif etype == 'p':
            cleaned = clean_md_formatting(content)
            if cleaned.strip():
                story.append(Paragraph(cleaned, p_style))
        elif etype == 'li':
            cleaned = clean_md_formatting(content)
            story.append(Paragraph(f"• {cleaned}", li_style))
        elif etype == 'oli':
            cleaned = clean_md_formatting(content)
            story.append(Paragraph(cleaned, li_style))
        elif etype == 'code':
            for cl in content.split('\n')[:20]:  # Limit code lines
                story.append(Paragraph(cl, code_style))
        elif etype == 'table':
            if len(content) > 0:
                # Clean table data
                table_data = []
                for row in content[:50]:  # Limit rows
                    table_data.append([Paragraph(clean_md_formatting(c), ParagraphStyle('TC', fontName='SimSun', fontSize=8, leading=11)) for c in row])

                if table_data:
                    # Calculate column widths
                    ncols = max(len(r) for r in table_data)
                    avail = doc.width
                    col_w = avail / ncols if ncols > 0 else avail

                    t = Table(table_data, colWidths=[col_w]*ncols)
                    t.setStyle(TableStyle([
                        ('FONTNAME', (0,0), (-1,-1), 'SimSun'),
                        ('FONTSIZE', (0,0), (-1,-1), 8),
                        ('BACKGROUND', (0,0), (-1,0), HexColor('#e8e8e8')),
                        ('TEXTCOLOR', (0,0), (-1,0), black),
                        ('ALIGN', (0,0), (-1,-1), 'LEFT'),
                        ('VALIGN', (0,0), (-1,-1), 'TOP'),
                        ('GRID', (0,0), (-1,-1), 0.5, HexColor('#cccccc')),
                        ('ROWBACKGROUNDS', (0,1), (-1,-1), [white, HexColor('#f9f9f9')]),
                        ('TOPPADDING', (0,0), (-1,-1), 3),
                        ('BOTTOMPADDING', (0,0), (-1,-1), 3),
                        ('LEFTPADDING', (0,0), (-1,-1), 4),
                        ('RIGHTPADDING', (0,0), (-1,-1), 4),
                    ]))
                    story.append(Spacer(1, 4))
                    story.append(t)
                    story.append(Spacer(1, 6))
        elif etype == 'blank':
            story.append(Spacer(1, 4))

    doc.build(story)
    print(f"  OK: {pdf_path} ({os.path.getsize(pdf_path)//1024}KB)")

def main():
    os.makedirs(PDF_DIR, exist_ok=True)

    print("=== 重新生成 PDF（中文字体支持）===\n")

    for pdf_name, (md_rel, title) in MD_FILES.items():
        md_path = os.path.join(MD_DIR, md_rel)
        pdf_path = os.path.join(PDF_DIR, f"{pdf_name}.pdf")
        print(f"[{pdf_name}] {title}")
        try:
            build_pdf(md_path, pdf_path, title)
        except Exception as e:
            print(f"  ERROR: {e}")

    print(f"\n完成！输出目录: {PDF_DIR}")

if __name__ == '__main__':
    main()
