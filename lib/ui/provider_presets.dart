part of '../main.dart';

// Model-provider presets shown in MODEL SETTINGS (OpenAI-compatible plus the
// native Anthropic/Gemini entries).

class _ProviderPreset {
  const _ProviderPreset({
    required this.label,
    required this.baseUrl,
    required this.models,
    required this.keyHint,
  });

  final String label;
  final String baseUrl; // empty => custom, leave existing fields untouched
  final List<String> models;
  final String keyHint;
}

const _customProviderLabel = 'Custom / OpenAI-compatible';

// Most providers here speak the OpenAI Chat Completions protocol, so only the
// Base URL, example models, and where-to-get-the-key hint differ. The two
// "(native)" presets point at api.anthropic.com and Google's generateContent
// endpoint; AgentService.detectProviderProtocol() routes those through the
// native adapters (x-api-key / x-goog-api-key), so no OpenAI-compat proxy is
// needed. Claude and Gemini can also be reached via OpenRouter or Google's
// OpenAI-compatible endpoint below.
const _providerPresets = <_ProviderPreset>[
  _ProviderPreset(
    label: _customProviderLabel,
    baseUrl: '',
    models: [],
    keyHint: 'Base URL & model bebas selama endpoint OpenAI-compatible.',
  ),
  _ProviderPreset(
    label: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
    models: ['gpt-4.1', 'gpt-4o', 'o4-mini'],
    keyHint: 'API key dari platform.openai.com/api-keys',
  ),
  _ProviderPreset(
    label: 'Anthropic Claude (native)',
    baseUrl: 'https://api.anthropic.com',
    models: ['claude-opus-4-8', 'claude-sonnet-5', 'claude-haiku-4-5'],
    keyHint: 'API key dari console.anthropic.com — protokol Messages native.',
  ),
  _ProviderPreset(
    label: 'Google Gemini (native)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash'],
    keyHint:
        'API key dari aistudio.google.com/apikey — generateContent native.',
  ),
  _ProviderPreset(
    label: 'OpenRouter (Claude, Gemini, dll)',
    baseUrl: 'https://openrouter.ai/api/v1',
    models: [
      'anthropic/claude-sonnet-4',
      'google/gemini-2.5-pro',
      'openai/gpt-4.1',
    ],
    keyHint: 'Satu key untuk banyak model — openrouter.ai/keys',
  ),
  _ProviderPreset(
    label: 'AgentRouter (OpenAI-compatible)',
    baseUrl: 'https://agentrouter.org/v1',
    models: ['gpt-5.5', 'glm-5.1', 'kimi-k2.6'],
    keyHint:
        'API key dari agentrouter.org. Jika muncul "unauthorized client '
        'detected", minta AgentRouter mengizinkan YOUNZCODE sebagai client.',
  ),
  _ProviderPreset(
    label: 'Google Gemini (OpenAI-compatible)',
    baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
    models: ['gemini-2.5-pro', 'gemini-2.5-flash'],
    keyHint: 'API key dari aistudio.google.com/apikey',
  ),
  _ProviderPreset(
    label: 'NVIDIA NIM',
    baseUrl: 'https://integrate.api.nvidia.com/v1',
    models: ['deepseek-ai/deepseek-r1', 'meta/llama-3.3-70b-instruct'],
    keyHint: 'API key dari build.nvidia.com',
  ),
  _ProviderPreset(
    label: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
    models: ['llama-3.3-70b-versatile', 'moonshotai/kimi-k2-instruct'],
    keyHint: 'API key dari console.groq.com/keys',
  ),
  _ProviderPreset(
    label: 'DeepSeek',
    baseUrl: 'https://api.deepseek.com',
    models: ['deepseek-chat', 'deepseek-reasoner'],
    keyHint: 'API key dari platform.deepseek.com',
  ),
  _ProviderPreset(
    label: 'Mistral AI',
    baseUrl: 'https://api.mistral.ai/v1',
    models: [
      'mistral-large-latest',
      'codestral-latest',
      'mistral-small-latest',
    ],
    keyHint: 'API key dari console.mistral.ai',
  ),
  _ProviderPreset(
    label: 'Cohere',
    baseUrl: 'https://api.cohere.com/compatibility/v1',
    models: ['command-a-03-2025', 'command-r-plus-08-2024'],
    keyHint: 'API key dari dashboard.cohere.com',
  ),
  _ProviderPreset(
    label: 'Together AI',
    baseUrl: 'https://api.together.xyz/v1',
    models: [
      'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      'Qwen/Qwen2.5-Coder-32B-Instruct',
    ],
    keyHint: 'API key dari api.together.ai/settings/api-keys',
  ),
  _ProviderPreset(
    label: 'Fireworks AI',
    baseUrl: 'https://api.fireworks.ai/inference/v1',
    models: [
      'accounts/fireworks/models/llama-v3p1-70b-instruct',
      'accounts/fireworks/models/qwen2p5-coder-32b-instruct',
    ],
    keyHint: 'API key dari fireworks.ai/account/api-keys',
  ),
  _ProviderPreset(
    label: 'Cerebras',
    baseUrl: 'https://api.cerebras.ai/v1',
    models: ['llama-3.3-70b', 'qwen-3-32b'],
    keyHint: 'API key dari cloud.cerebras.ai',
  ),
  _ProviderPreset(
    label: 'SambaNova Cloud',
    baseUrl: 'https://api.sambanova.ai/v1',
    models: ['Meta-Llama-3.3-70B-Instruct', 'DeepSeek-R1'],
    keyHint: 'API key dari cloud.sambanova.ai',
  ),
  _ProviderPreset(
    label: 'xAI Grok',
    baseUrl: 'https://api.x.ai/v1',
    models: ['grok-3', 'grok-3-mini'],
    keyHint: 'API key dari console.x.ai',
  ),
  _ProviderPreset(
    label: 'Perplexity',
    baseUrl: 'https://api.perplexity.ai',
    models: ['sonar-pro', 'sonar'],
    keyHint: 'API key dari perplexity.ai/settings/api',
  ),
  _ProviderPreset(
    label: 'Moonshot AI (Kimi)',
    baseUrl: 'https://api.moonshot.ai/v1',
    models: ['kimi-k2-0711-preview', 'moonshot-v1-128k'],
    keyHint: 'API key dari platform.moonshot.ai',
  ),
  _ProviderPreset(
    label: 'Zhipu AI (GLM)',
    baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    models: ['glm-4.5', 'glm-4.5-air'],
    keyHint: 'API key dari open.bigmodel.cn',
  ),
  _ProviderPreset(
    label: 'SiliconFlow',
    baseUrl: 'https://api.siliconflow.cn/v1',
    models: ['Qwen/Qwen3-32B', 'deepseek-ai/DeepSeek-R1'],
    keyHint: 'API key dari cloud.siliconflow.cn/account/ak',
  ),
  _ProviderPreset(
    label: 'Hugging Face Inference',
    baseUrl: 'https://router.huggingface.co/v1',
    models: ['Qwen/Qwen3-32B', 'meta-llama/Llama-3.3-70B-Instruct'],
    keyHint: 'Access token dari huggingface.co/settings/tokens',
  ),
  _ProviderPreset(
    label: '9router (lokal)',
    baseUrl: 'http://127.0.0.1:20128/v1',
    models: [],
    keyHint:
        'Jalankan 9router lokal, sambungkan provider di dashboard-nya; '
        'model & API key mengikuti dashboard tersebut.',
  ),
  _ProviderPreset(
    label: 'Ollama (lokal)',
    baseUrl: 'http://localhost:11434/v1',
    models: ['qwen2.5-coder', 'llama3.1'],
    keyHint: 'Server lokal Ollama; API key boleh diisi apa saja.',
  ),
];

_ProviderPreset _presetForBaseUrl(String url) {
  final normalized = url.trim().replaceAll(RegExp(r'/+$'), '').toLowerCase();
  for (final preset in _providerPresets) {
    if (preset.baseUrl.isNotEmpty &&
        preset.baseUrl.toLowerCase().replaceAll(RegExp(r'/+$'), '') ==
            normalized) {
      return preset;
    }
  }
  return _providerPresets.first;
}
