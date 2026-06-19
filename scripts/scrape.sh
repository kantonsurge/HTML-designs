#!/usr/bin/env bash
# Scrape templatemo.com -> extract each template into a category folder.
# Self-contained, deduped by canonical name. Commits + pushes in batches.
set -uo pipefail
REPO="/c/tmp/HTML-designs"
WORK="/c/tmp/tm-work"; mkdir -p "$WORK"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
LOG="$WORK/run.log"; : > "$LOG"
MAN="$REPO/manifest.csv"; [ -f "$MAN" ] || echo "name,category,tags,page" > "$MAN"

# specific verticals first so they win over generic business/corporate
CATS="restaurant cafe food coffee bakery hotel travel tour real-estate property medical health dental hospital fitness gym yoga spa beauty salon education school university course photography photo wedding music band event conference fashion clothing jewelry ecommerce shop store finance bank accounting insurance crypto construction architecture interior furniture automotive car repair gaming game esports nonprofit charity church religion law legal agency creative marketing seo advertising software saas app mobile cloud startup ai technology tech blog magazine news portfolio resume cv personal vcard wedding landing onepage onepage-template corporate business"

slugs="$WORK/slugs.txt"; : > "$slugs"
echo "[*] collecting template slugs..." | tee -a "$LOG"
for p in $(seq 1 60); do
  curl -s -A "$UA" "https://templatemo.com/page/$p" \
    | grep -oE '/tm-[0-9]+[a-z0-9-]*' >> "$slugs"
  sleep 1
done
sort -u "$slugs" -o "$slugs"
total=$(wc -l < "$slugs"); echo "[*] $total unique templates found" | tee -a "$LOG"

i=0; got=0
while read -r slug; do
  i=$((i+1))
  page="https://templatemo.com$slug"
  html=$(curl -s -A "$UA" "$page")
  dl=$(echo "$html" | grep -oE '/download/templatemo_[0-9]+_[a-z0-9_]+' | head -1)
  [ -z "$dl" ] && { echo "[$i/$total] NO-DL $slug" | tee -a "$LOG"; continue; }
  name=$(basename "$dl")                       # templatemo_NNN_name
  # dedupe: skip if this name already exists anywhere
  if find "$REPO/templates" -maxdepth 2 -type d -name "$name" 2>/dev/null | grep -q .; then
    echo "[$i/$total] DUP  $name" | tee -a "$LOG"; continue
  fi
  tags=$(echo "$html" | grep -oE 'tag/[a-z0-9-]+' | sed 's#tag/##' | sort -u | tr '\n' '|' | sed 's/|$//')
  cat="misc"
  for c in $CATS; do echo "$tags" | tr '|' '\n' | grep -qx "$c" && { cat="$c"; break; }; done
  zip="$WORK/$name.zip"
  curl -s -L -A "$UA" -o "$zip" "https://templatemo.com$dl"
  if ! unzip -tq "$zip" >/dev/null 2>&1; then echo "[$i/$total] BADZIP $name" | tee -a "$LOG"; rm -f "$zip"; continue; fi
  mkdir -p "$REPO/templates/$cat"
  unzip -q -o "$zip" -d "$REPO/templates/$cat/"
  rm -f "$zip"
  echo "$name,$cat,$tags,$page" >> "$MAN"
  got=$((got+1))
  echo "[$i/$total] OK   $name -> $cat" | tee -a "$LOG"
  # batch commit + push every 40 successes
  if [ $((got % 40)) -eq 0 ]; then
    cd "$REPO" && git add -A >/dev/null 2>&1 && git commit -q -m "Add templatemo templates (batch, $got so far)" >/dev/null 2>&1 && git push -q origin HEAD 2>&1 | tail -1
  fi
  sleep 2
done < "$slugs"

# final README + manifest commit
cd "$REPO"
{
  echo "# HTML Designs — template library"
  echo
  echo "Self-contained website templates, one folder each, sorted by category. Every folder has its own \`assets/\` (css, js, images, fonts) — no cross-template conflicts."
  echo
  echo "## Categories"
  for d in templates/*/; do
    [ -d "$d" ] || continue
    n=$(find "$d" -maxdepth 1 -mindepth 1 -type d | wc -l)
    echo "- **$(basename "$d")** — $n"
  done | sort
  echo
  echo "_Total: $(find templates -maxdepth 2 -mindepth 2 -type d | wc -l) templates._ See \`manifest.csv\`."
} > README.md
git add -A && git commit -q -m "Finalize templatemo library: $got templates + README + manifest" && git push -q origin HEAD 2>&1 | tail -2
echo "[*] DONE — $got templates" | tee -a "$LOG"
