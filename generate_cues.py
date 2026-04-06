import os
import sys
import json
import urllib.request
import base64

API_KEY = os.environ.get("GOOGLE_TTS_API_KEY")

if not API_KEY:
    print("Error: GOOGLE_TTS_API_KEY environment variable not set.")
    print("Please export it before running, e.g.:")
    print("export GOOGLE_TTS_API_KEY='your_api_key_here'")
    sys.exit(1)

OUTPUT_DIR = "./generated_tts_assets"
os.makedirs(OUTPUT_DIR, exist_ok=True)

def generate_tts(ssml, voice_name, output_filename):
    url = f"https://texttospeech.googleapis.com/v1/text:synthesize?key={API_KEY}"
    
    payload = {
        "input": {"ssml": ssml},
        "voice": {
            "name": voice_name,
            "languageCode": "en-US"
        },
        "audioConfig": {
            "audioEncoding": "MP3"
        }
    }
    
    req = urllib.request.Request(url, data=json.dumps(payload).encode('utf-8'))
    req.add_header("Content-Type", "application/json")
    
    output_path = os.path.join(OUTPUT_DIR, output_filename)
    
    try:
        with urllib.request.urlopen(req) as response:
            result = json.loads(response.read().decode('utf-8'))
            audio_content = base64.b64decode(result["audioContent"])
            with open(output_path, "wb") as out:
                out.write(audio_content)
            print(f"✅ Generated: {output_path}  (Voice: {voice_name})")
    except urllib.error.HTTPError as e:
        print(f"❌ Failed to generate {output_filename}: HTTP {e.code} - {e.read().decode('utf-8')}")
    except Exception as e:
        print(f"❌ Failed to generate {output_filename}: {e}")

if __name__ == "__main__":
    # SSML definitions
    intro_ssml = """<speak>
  <p>
    You’ve used your monthly Enhanced Audio.
    <break time="300ms"/>
    <emphasis level="moderate">Subscribe</emphasis> to keep listening with Enhanced Audio.
  </p>
</speak>"""
    
    basic_ssml = """<speak>
  <p>
    Now continuing in Basic Audio.
  </p>
</speak>"""
    
    # Neural2 voice definitions
    voices = {
        "female": "en-US-Neural2-F",
        "male": "en-US-Neural2-D"
    }

    print(f"Synthesizing {len(voices) * 2} files into {OUTPUT_DIR}/...\n")

    for gender, voice_id in voices.items():
        generate_tts(intro_ssml, voice_id, f"enhanced_exhaustion_intro_{gender}.mp3")
        generate_tts(basic_ssml, voice_id, f"enhanced_exhaustion_basic_{gender}.mp3")
    
    print("\nDone!")
