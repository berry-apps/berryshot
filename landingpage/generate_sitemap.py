#!/usr/bin/env python3
import os
import sys
from datetime import datetime

# Script to generate sitemap.xml and robots.txt dynamically for the landing page.
# Usage: python3 generate_sitemap.py [domain_url]
# Example: python3 generate_sitemap.py https://notex.work

DEFAULT_DOMAIN = "https://notex.work"
domain = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_DOMAIN
domain = domain.rstrip('/')

print(f"Generating SEO files for domain: {domain}")

sitemap_template = """<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{urls}
</urlset>"""

url_template = """  <url>
    <loc>{loc}</loc>
    <lastmod>{lastmod}</lastmod>
    <changefreq>{changefreq}</changefreq>
    <priority>{priority}</priority>
  </url>"""

# Scan the current directory (landingpage) or fallback
search_dir = "landingpage" if os.path.exists("landingpage") else "."
html_files = []

for file in os.listdir(search_dir):
    if file.endswith(".html"):
        html_files.append(file)

url_nodes = []
for file in sorted(html_files):
    filepath = os.path.join(search_dir, file)
    mtime = os.path.getmtime(filepath)
    lastmod = datetime.fromtimestamp(mtime).strftime("%Y-%m-%d")
    
    # Map filenames to path rules
    if file == "index.html":
        loc = f"{domain}/"
        priority = "1.0"
        changefreq = "weekly"
    else:
        loc = f"{domain}/{file}"
        priority = "0.8"
        changefreq = "monthly"
        
    url_nodes.append(url_template.format(
        loc=loc,
        lastmod=lastmod,
        changefreq=changefreq,
        priority=priority
    ))

sitemap_content = sitemap_template.format(urls="\n".join(url_nodes))

# Write sitemap.xml
sitemap_path = os.path.join(search_dir, "sitemap.xml")
with open(sitemap_path, "w", encoding="utf-8") as f:
    f.write(sitemap_content)
print(f"✓ Generated {sitemap_path}")

# Write robots.txt
robots_content = f"""User-agent: *
Allow: /

Sitemap: {domain}/sitemap.xml
"""
robots_path = os.path.join(search_dir, "robots.txt")
with open(robots_path, "w", encoding="utf-8") as f:
    f.write(robots_content)
print(f"✓ Generated {robots_path}")
print("SEO automation assets created successfully!")
