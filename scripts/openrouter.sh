#!/bin/bash

set -euo pipefail

updateTime="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
repoRoot="$(cd "$(dirname "$0")/.." && pwd)"
readmeFile="${repoRoot}/README.md"

python3 - <<'PY' "${readmeFile}" "${updateTime}"
import json
import sys
import urllib.request

readmeFile = sys.argv[1]
updateTime = sys.argv[2]

# ── Fetch catalog (rich model data) ──────────────────────────
catalogUrl = 'https://openrouter.ai/api/frontend/v1/catalog/models'
with urllib.request.urlopen(catalogUrl, timeout=30) as httpResponse:
  catalogData = json.loads(httpResponse.read().decode())

modelList = catalogData.get('data', [])

# ── Fetch pricing from official Models API ───────────────────
pricingUrl = 'https://openrouter.ai/api/v1/models'
pricingLookup = {}
try:
  with urllib.request.urlopen(pricingUrl, timeout=30) as httpResponse:
    modelsApiData = json.loads(httpResponse.read().decode())
  for pm in modelsApiData.get('data', []):
    pid = pm.get('id', '')
    pr = pm.get('pricing', {})
    pricingLookup[pid] = pr
    # Also index without ':free' suffix so catalog slugs match
    if ':free' in pid:
      baseSlug = pid.replace(':free', '')
      if baseSlug not in pricingLookup:
        pricingLookup[baseSlug] = pr
except Exception:
  pass  # pricing is optional — table still works without it

def format_pricing(pricing):
  """Return a short human-friendly pricing string."""
  if not pricing:
    return '-'
  try:
    prompt = float(pricing.get('prompt', '-1'))
    completion = float(pricing.get('completion', '-1'))
  except (ValueError, TypeError):
    return '-'
  # -1 means not applicable (e.g. router models)
  if prompt == -1 and completion == -1:
    return '-'
  if prompt == 0 and completion == 0:
    return '**FREE**'
  # Show input price per million tokens (most readable)
  ppm = prompt * 1_000_000
  if ppm > 0:
    return f'${ppm:.4f}/M in'
  # Fallback: completion-only pricing
  cpm = completion * 1_000_000
  if cpm > 0:
    return f'${cpm:.4f}/M out'
  return '-'

tableRows = []
for modelData in modelList:
  modelSlug = modelData.get('slug', '')
  modelName = modelData.get('name', modelSlug)
  contextLength = modelData.get('context_length', 0)
  modifiedAt = modelData.get('updated_at', '')
  capList = []
  inputMods = modelData.get('input_modalities', [])
  if 'text' in inputMods:
    capList.append('text')
  if 'image' in inputMods:
    capList.append('vision')
  if 'audio' in inputMods:
    capList.append('audio')
  if 'video' in inputMods:
    capList.append('video')
  outputMods = modelData.get('output_modalities', [])
  if 'image' in outputMods:
    capList.append('image-gen')
  if 'video' in outputMods:
    capList.append('video-gen')
  if modelData.get('supports_reasoning', False):
    capList.append('reasoning')
  modelEndpoint = modelData.get('endpoint') or {}
  if modelEndpoint.get('supports_tool_parameters', False):
    capList.append('tools')
  if contextLength:
    sizeText = f'{contextLength:,} tokens'
  else:
    sizeText = '-'
  if capList:
    capText = ', '.join(capList)
  else:
    capText = '(none)'
  # ── Pricing ────────────────────────────────────────────────
  pricingInfo = pricingLookup.get(modelSlug, {})
  pricingText = format_pricing(pricingInfo)
  # ── Link ───────────────────────────────────────────────────
  modelLink = f'https://openrouter.ai/models/{modelSlug}'
  tableRows.append((modelSlug, sizeText, pricingText, modifiedAt, capText, modelLink))

tableRows.sort(key=lambda rowItem: (rowItem[3] or '', rowItem[0].lower()), reverse=True)
readmeLines = [
  '# OpenRouter Catalog',
  '',
  'Fetch cloud models, inspect capabilities, publish clickable table automatically.',
  '',
  f'## Available Cloud Models ({len(modelList)})',
  '',
  '| model name | context | pricing | modified at | capability tags | official link |',
  '| --- | --- | --- | --- | --- | --- |'
]
for modelSlug, sizeText, pricingText, modifiedAt, capText, modelLink in tableRows:
  readmeLines.append(
    f'| `{modelSlug}` | `{sizeText}` | {pricingText} | `{modifiedAt}` | `{capText}` | [Open]({modelLink}) |'
  )
readmeLines.extend([
  '',
  '## License',
  '',
  'This project is licensed under the MIT license. See the [LICENSE](LICENSE) file for more info.',
  ''
])

with open(readmeFile, 'w', encoding='utf-8') as fileHandle:
  fileHandle.write('\n'.join(readmeLines))
PY

git add "${readmeFile}"
git config --local user.name "NeaByteLab"
git config --local user.email "209737579+NeaByteLab@users.noreply.github.com"
if git diff --cached --quiet; then
  echo "No README changes to commit"
else
  git commit -m "chore(bot): update cloud model catalog at ${updateTime} 🤖"
fi