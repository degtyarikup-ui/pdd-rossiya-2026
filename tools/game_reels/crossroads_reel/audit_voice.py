# coding: utf-8
"""Independent listening audit of the finished narration, saved beside the run."""
import argparse,json,subprocess,warnings
from pathlib import Path
warnings.filterwarnings('ignore')
from google import genai
from google.oauth2.credentials import Credentials
p=argparse.ArgumentParser();p.add_argument('--out',required=True,type=Path);a=p.parse_args();d=a.out.resolve()
project=subprocess.check_output(['gcloud','config','get-value','project'],text=True,stderr=subprocess.DEVNULL).strip()
token=subprocess.check_output(['gcloud','auth','print-access-token'],text=True,stderr=subprocess.DEVNULL).strip()
client=genai.Client(vertexai=True,project=project,location='global',credentials=Credentials(token),http_options={'timeout':90000})
voice=json.loads((d/'voice.json').read_text())
prompt='Прослушай русскую озвучку короткого видео. Перепиши именно услышанное, не исправляя окончания по контексту. Оцени naturalness, expressiveness, clarity от 1 до 10. Укажи wrong_or_unclear_words и delivery_issues. Если ошибок нет, пустые массивы. Не оценивай видеоряд, которого нет. Верни JSON с полями heard_transcript, naturalness, expressiveness, clarity, wrong_or_unclear_words, delivery_issues. Ожидаемый текст только для сравнения: '+ ' '.join(x['text'] for x in voice)
response=client.models.generate_content(model='gemini-2.5-flash',contents=[prompt,genai.types.Part.from_bytes(data=(d/'audio/speech.wav').read_bytes(),mime_type='audio/wav')],config={'response_mime_type':'application/json','temperature':.1})
result=json.loads(response.text);(d/'voice-audit.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');print(json.dumps(result,ensure_ascii=False,indent=2))
if result.get('wrong_or_unclear_words') or min(result.get(k,0) for k in ['naturalness','expressiveness','clarity'])<8:raise SystemExit('VOICE_REVIEW_REQUIRED')
