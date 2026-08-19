#!/usr/bin/env python3
import argparse
import json
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, HTTPServer

# Simple dictionary of mock translations for quick tests
MOCK_DICT = {
    "hello": {"pt": "olá", "es": "hola", "fr": "bonjour", "de": "hallo", "en": "hello"},
    "world": {"pt": "mundo", "es": "mundo", "fr": "monde", "de": "welt", "en": "world"},
    "how are you?": {"pt": "como vai você?", "es": "cómo estás?", "fr": "comment ça va?", "de": "wie geht es dir?", "en": "how are you?"},
    "good morning": {"pt": "bom dia", "es": "buenos días", "fr": "bonjour", "de": "guten morgen", "en": "good morning"},
    "prism translate": {"pt": "Prism Tradutor", "es": "Prism Traductor", "fr": "Traducteur Prism", "de": "Prism Übersetzer", "en": "Prism Translate"}
}

class TranslationMockHandler(BaseHTTPRequestHandler):
    proxy_url = None

    def log_message(self, format, *args):
        # Disable default HTTP logging to keep stdout clean
        pass

    def do_OPTIONS(self):
        # Enable CORS
        self.send_response(200)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()

    def do_POST(self):
        if self.path != '/translate':
            self.send_error(404, "Endpoint not found. Use /translate")
            return

        content_length = int(self.headers.get('Content-Length', 0))
        post_data = self.rfile.read(content_length)

        try:
            request_data = json.loads(post_data.decode('utf-8'))
        except json.JSONDecodeError:
            self.send_error(400, "Invalid JSON body")
            return

        print("\n📥 --- Chamada de Tradução Recebida ---")
        print(f"Cabeçalhos: {dict(self.headers)}")
        print(f"Corpo: {json.dumps(request_data, indent=2, ensure_ascii=False)}")

        # Prism default template uses `text`; LibreTranslate-style bodies use `q`.
        text = (
            request_data.get('text')
            or request_data.get('q')
            or request_data.get('content')
            or ''
        )
        source = request_data.get('source') or request_data.get('from') or ''
        target = request_data.get('target') or request_data.get('to') or 'en'
        if isinstance(target, str):
            target = target.lower()
        field = 'q' if request_data.get('q') and not request_data.get('text') else 'text'
        print(
            f"Texto extraído ({len(text)} caracteres) via {field} "
            f"· source={source or 'auto'} · target={target}"
        )

        translated_text = ""
        used_proxy = False

        if self.proxy_url:
            # We want to proxy the request to an actual LibreTranslate instance.
            # LibreTranslate uses body parameters: q, source, target, format
            payload = {
                "q": text,
                "source": source if source else "auto",
                "target": target,
                "format": "text"
            }
            print(f"🔄 Encaminhando para LibreTranslate em {self.proxy_url}...")
            print(f"Payload: {json.dumps(payload, indent=2, ensure_ascii=False)}")
            
            req = urllib.request.Request(
                self.proxy_url,
                data=json.dumps(payload).encode('utf-8'),
                headers={'Content-Type': 'application/json'}
            )
            try:
                with urllib.request.urlopen(req, timeout=10) as response:
                    resp_data = json.loads(response.read().decode('utf-8'))
                    translated_text = resp_data.get('translatedText', '')
                    used_proxy = True
                    print(f"✅ Resposta do Proxy: {json.dumps(resp_data, indent=2, ensure_ascii=False)}")
            except urllib.error.HTTPError as e:
                detail = e.read().decode('utf-8', errors='replace') if e.fp else ''
                print(
                    f"❌ Proxy HTTP {e.code}: {e.reason}"
                    + (f" · {detail[:240]}" if detail else "")
                )
                translated_text = f"[FALLBACK -> {target.upper()}] {text}"
            except urllib.error.URLError as e:
                print(f"❌ Falha ao conectar ao Proxy (LibreTranslate): {e}")
                translated_text = f"[FALLBACK -> {target.upper()}] {text}"
            except Exception as e:
                print(f"❌ Erro no Proxy: {e}")
                translated_text = f"[ERROR -> {target.upper()}] {text}"
        
        if not used_proxy:
            # Mock translator
            norm_text = text.strip().lower()
            if norm_text in MOCK_DICT and target in MOCK_DICT[norm_text]:
                translated_text = MOCK_DICT[norm_text][target]
                print(f"✨ Tradução mockada (dicionário): {translated_text}")
            else:
                # Fallback: reverse the string so you can see it changed
                translated_text = f"[MOCK -> {target.upper()}]: {text[::-1]}"
                print(f"✨ Tradução mockada (texto invertido): {translated_text}")

        # Send response back to Prism (using Prism's expected path: 'translatedText')
        response_body = {
            "translatedText": translated_text
        }

        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(response_body).encode('utf-8'))
        print(f"📤 Respondido para o Prism: {json.dumps(response_body, ensure_ascii=False)}")
        print("---------------------------------------\n")

def run(port, proxy):
    TranslationMockHandler.proxy_url = proxy
    server_address = ('', port)
    httpd = HTTPServer(server_address, TranslationMockHandler)
    mode = f"Modo Proxy para {proxy}" if proxy else "Modo Mock"
    print(f"🚀 Iniciando servidor de testes HTTP para o Prism na porta {port} ({mode})...")
    print(f"Aguardando requisições em http://localhost:{port}/translate")
    print("Dica: Use Ctrl+C para encerrar o servidor.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nParando servidor de testes...")
        httpd.server_close()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description="Servidor de testes local para o Custom HTTP Provider do Prism.")
    parser.add_argument('--port', type=int, default=8080, help="Porta para rodar o servidor de testes (padrão: 8080)")
    parser.add_argument('--proxy', type=str, default=None, help="Endpoint real do LibreTranslate para encaminhar as requisições (ex: http://localhost:5000/translate)")
    args = parser.parse_args()
    run(args.port, args.proxy)
