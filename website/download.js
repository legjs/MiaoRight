(function () {
  'use strict';

  // A Mac user agent can say Intel even on Apple silicon. Only use
  // explicit architecture hints or the GPU's unmasked renderer name.
  function identifyArchitecture(platform, architecture, renderer) {
    if (!/mac/i.test(platform)) return null;
    if (/apple\s+m\d+\b/i.test(renderer)) return 'arm64';
    if (/^(arm|arm64|aarch64)$/i.test(architecture)) return 'arm64';
    if (/^(x86|x86_64|x64|amd64)$/i.test(architecture)) return 'x86_64';
    if (/intel|amd|radeon|nvidia/i.test(renderer)) return 'x86_64';
    return null;
  }

  let manuallySelected = false;
  const status = document.getElementById('detection-status');
  const choices = document.querySelectorAll('input[name="architecture"]');
  const button = document.getElementById('download-button');

  function selectArchitecture(architecture) {
    const link = document.querySelector('a[data-arch="' + architecture + '"]');
    if (!link) return;
    for (const choice of choices) choice.checked = choice.value === architecture;
    button.href = link.href;
    button.textContent = architecture === 'arm64' ? '下载 Apple 芯片版' : '下载 Intel 芯片版';
    document.getElementById('recommended-download').hidden = false;
  }

  for (const choice of choices) {
    choice.addEventListener('change', function () {
      manuallySelected = true;
      selectArchitecture(choice.value);
      status.textContent = '已按你的选择切换下载版本。';
    });
  }

  async function recommendArchitecture() {
    let architecture = '';
    let renderer = '';
    let platform = navigator.userAgentData?.platform || navigator.platform || '';
    try {
      if (navigator.userAgentData?.getHighEntropyValues) {
        const hints = await navigator.userAgentData.getHighEntropyValues(['architecture']);
        architecture = hints.architecture || '';
      }
    } catch (_) { /* Continue with renderer detection or manual selection. */ }
    try {
      const canvas = document.createElement('canvas');
      const gl = canvas.getContext('webgl');
      if (gl) {
        const extension = gl.getExtension('WEBGL_debug_renderer_info');
        if (extension) renderer = gl.getParameter(extension.UNMASKED_RENDERER_WEBGL) || '';
        gl.getExtension('WEBGL_lose_context')?.loseContext();
      }
    } catch (_) { /* Browsers may restrict GPU information. */ }
    if (manuallySelected) return;
    const detected = identifyArchitecture(platform, architecture, renderer);
    if (detected) {
      selectArchitecture(detected);
      status.textContent = '根据浏览器信息，推荐' + (detected === 'arm64' ? ' Apple 芯片版。' : ' Intel 芯片版。') + '你也可以手动切换。';
    } else {
      status.textContent = /mac/i.test(platform)
        ? '浏览器未提供足够的芯片信息。可在苹果菜单「关于本机」查看后选择。'
        : '请为要安装妙右的 Mac 选择芯片类型。';
    }
  }

  recommendArchitecture();
}());
