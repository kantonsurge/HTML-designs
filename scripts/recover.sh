#!/usr/bin/env bash
# Recovery pass: re-fetch any templatemo template missed by the main run
# (transient NO-DL/rate-limit). Idempotent: skips folders that already exist,
# deriving the expected name from the slug so done ones need no network.
set -uo pipefail
REPO="/c/tmp/HTML-designs"; WORK="/c/tmp/tm-work"; mkdir -p "$WORK"
UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64)"
LOG="$WORK/recover.log"; : > "$LOG"
MAN="$REPO/manifest.csv"; [ -f "$MAN" ] || echo "name,category,tags,page" > "$MAN"
CATS="restaurant cafe food coffee bakery hotel travel tour real-estate property medical health dental hospital fitness gym yoga spa beauty salon education school university course photography photo wedding music band event conference fashion clothing jewelry ecommerce shop store finance bank accounting insurance crypto construction architecture interior furniture automotive car repair gaming game esports nonprofit charity church religion law legal agency creative marketing seo advertising software saas app mobile cloud startup ai technology tech blog magazine news portfolio resume cv personal vcard wedding landing onepage corporate business"

# fetch a URL with up to 4 retries + backoff; echo body only if it contains a download link
fetch_template_html(){
  local url="$1" body=""
  for attempt in 1 2 3 4; do
    body=$(curl -s -A "$UA" --max-time 30 "$url")
    if echo "$body" | grep -q '/download/templatemo_'; then echo "$body"; return 0; fi
    sleep $((attempt*4))
  done
  return 1
}

slugs="$WORK/slugs.txt"
[ -s "$slugs" ] || { echo "no slugs file"; exit 1; }
total=$(wc -l < "$slugs"); i=0; got=0; fail=0
while read -r slug; do
  i=$((i+1)); slug="${slug#/}"                      # tm-NNN-name
  expname="templatemo_${slug#tm-}"; expname="${expname//-/_}"   # derived folder name
  if find "$REPO/templates" -maxdepth 2 -type d -name "$expname" 2>/dev/null | grep -q .; then
    continue                                         # already have it — no network
  fi
  page="https://templatemo.com/$slug"
  html=$(fetch_template_html "$page") || { echo "[$i/$total] FAIL $slug" | tee -a "$LOG"; fail=$((fail+1)); continue; }
  dl=$(echo "$html" | grep -oE '/download/templatemo_[0-9]+_[a-z0-9_]+' | head -1)
  name=$(basename "$dl")
  find "$REPO/templates" -maxdepth 2 -type d -name "$name" 2>/dev/null | grep -q . && continue
  tags=$(echo "$html" | grep -oE 'tag/[a-z0-9-]+' | sed 's#tag/##' | sort -u | tr '\n' '|' | sed 's/|$//')
  cat="misc"; for c in $CATS; do echo "$tags" | tr '|' '\n' | grep -qx "$c" && { cat="$c"; break; }; done
  zip="$WORK/$name.zip"; zok=0
  for za in 1 2 3 4 5; do
    curl -s -L -A "$UA" --max-time 180 -o "$zip" "https://templatemo.com$dl"
    if unzip -tq "$zip" >/dev/null 2>&1; then zok=1; break; fi
    rm -f "$zip"; sleep $((za*5))
  done
  if [ "$zok" -ne 1 ]; then echo "[$i/$total] BADZIP $name" | tee -a "$LOG"; fail=$((fail+1)); continue; fi
  mkdir -p "$REPO/templates/$cat"; unzip -q -o "$zip" -d "$REPO/templates/$cat/"; rm -f "$zip"
  echo "$name,$cat,$tags,$page" >> "$MAN"; got=$((got+1))
  echo "[$i/$total] RECOVERED $name -> $cat" | tee -a "$LOG"
  if [ $((got % 40)) -eq 0 ]; then
    cd "$REPO" && git add -A >/dev/null 2>&1 && git commit -q -m "Recover missed templatemo templates (+$got)" >/dev/null 2>&1 && git push -q origin HEAD 2>&1 | tail -1
  fi
  sleep 3
done < "$slugs"
cd "$REPO" && git add -A >/dev/null 2>&1 && git commit -q -m "Recovery pass complete: +$got recovered, $fail still failing" >/dev/null 2>&1 && git push -q origin HEAD 2>&1 | tail -1
echo "[*] RECOVERY DONE — recovered $got, failed $fail" | tee -a "$LOG"
