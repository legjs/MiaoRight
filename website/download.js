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

  const isEnglish = !document.documentElement.lang.toLowerCase().startsWith('zh');
  const text = isEnglish ? {
    apple: 'Download for Apple silicon',
    intel: 'Download for Intel',
    dmg: 'DMG',
    zip: 'ZIP',
    manual: 'Switched the download to your selection.',
    detectedApple: 'Based on your browser, we recommend the Apple silicon build. You can switch manually.',
    detectedIntel: 'Based on your browser, we recommend the Intel build. You can switch manually.',
    unknown: 'Your browser did not provide enough chip information. Check Apple menu → About This Mac and choose the matching build.',
    notMac: 'Choose the chip type for the Mac where you will install MiaoRight.'
  } : {
    apple: '下载 Apple 芯片版',
    intel: '下载 Intel 芯片版',
    dmg: 'DMG',
    zip: 'ZIP',
    manual: '已按你的选择切换下载版本。',
    detectedApple: '根据浏览器信息，推荐 Apple 芯片版。你也可以手动切换。',
    detectedIntel: '根据浏览器信息，推荐 Intel 芯片版。你也可以手动切换。',
    unknown: '浏览器未提供足够的芯片信息。可在苹果菜单「关于本机」查看后选择。',
    notMac: '请为要安装妙右的 Mac 选择芯片类型。'
  };

  let manuallySelected = false;
  const status = document.getElementById('detection-status');
  const choices = document.querySelectorAll('input[name="architecture"]');
  const button = document.getElementById('download-button');

  function selectArchitecture(architecture) {
    const link = document.querySelector('a[data-arch="' + architecture + '"]');
    if (!link) return;
    for (const choice of choices) choice.checked = choice.value === architecture;
    button.href = link.dataset.dmg || link.href;
    button.textContent = (architecture === 'arm64' ? text.apple : text.intel) + ' ' + (link.dataset.dmg ? text.dmg : text.zip);
    document.getElementById('recommended-download').hidden = false;
  }

  for (const choice of choices) {
    choice.addEventListener('change', function () {
      manuallySelected = true;
      selectArchitecture(choice.value);
      status.textContent = text.manual;
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
      status.textContent = detected === 'arm64' ? text.detectedApple : text.detectedIntel;
    } else {
      status.textContent = /mac/i.test(platform) ? text.unknown : text.notMac;
    }
  }

  recommendArchitecture();
}());
