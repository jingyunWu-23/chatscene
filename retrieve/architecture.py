import os

DEFAULT_OPENAI_COMPATIBLE_BASE_URL = (
    "https://ws-icf5wb5c3k7dbc7b.cn-beijing.maas.aliyuncs.com/compatible-mode/v1"
)

class LLMChat():
    def __init__(
        self,
        model_name='qwen-plus',
        backend='auto',
        api_key=None,
        base_url=None,
        trust_env=False,
    ):
        super(LLMChat, self).__init__()
        self.model_name = model_name
        self.backend = self._resolve_backend(model_name, backend)
        if self.backend == 'openai':
            from openai import OpenAI, OpenAIError
            import httpx

            try:
                api_key = api_key or os.getenv('OPENAI_API_KEY') or os.getenv('DASHSCOPE_API_KEY')
                base_url = base_url or os.getenv('OPENAI_BASE_URL') or DEFAULT_OPENAI_COMPATIBLE_BASE_URL
                http_client = httpx.Client(trust_env=trust_env)
                self.client = OpenAI(api_key=api_key, base_url=base_url, http_client=http_client)
            except (OpenAIError, ValueError) as exc:
                raise RuntimeError(
                    "OpenAI-compatible API client initialization failed. "
                    "Set OPENAI_API_KEY or DASHSCOPE_API_KEY, or pass --api_key. If you use a third-party "
                    "OpenAI-compatible endpoint, also set OPENAI_BASE_URL or pass --base_url. "
                    "Environment proxies are ignored by default; pass --use_env_proxy only if your proxy URL "
                    "is valid for httpx, for example socks5://127.0.0.1:7897."
                ) from exc
        else:
            import torch
            import transformers

            self.pipeline = transformers.pipeline(
                "text-generation",
                model=model_name,
                model_kwargs={"torch_dtype": torch.bfloat16},
                device="cuda",
            )

    @staticmethod
    def _resolve_backend(model_name, backend):
        if backend != 'auto':
            return backend
        local_prefixes = ('meta-', 'mistralai/', 'Qwen/', 'THUDM/', 'baichuan-inc/', '/', '.')
        if model_name.startswith(local_prefixes):
            return 'transformers'
        return 'openai'

    def generate(self, messages, max_new_tokens = 500):
        if self.backend == 'openai':
            try:
                response = self.client.chat.completions.create(
                    model=self.model_name,
                    messages=messages,
                    temperature=0,
                )
            except Exception as exc:
                if exc.__class__.__name__ == 'NotFoundError':
                    raise RuntimeError(
                        f"Model {self.model_name!r} was not found by the OpenAI-compatible endpoint. "
                        "For Alibaba Cloud DashScope / Bailian compatible mode, use a model ID such as "
                        "'qwen-plus' instead of display names like 'Qwen3.7-plus'."
                    ) from exc
                raise
            return response.choices[0].message.content
        else:
            outputs = self.pipeline(
                messages,
                max_new_tokens=max_new_tokens,
                do_sample=False
            )
            generated = outputs[0]["generated_text"]
            if isinstance(generated, list):
                return generated[-1]["content"]
            return generated
