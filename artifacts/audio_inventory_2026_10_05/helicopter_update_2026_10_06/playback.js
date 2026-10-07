// Explicit controls remain visible even when the browser hides native audio UI.
let soundControlId = 0;
function attachSoundControls() {
document.querySelectorAll('audio:not([data-play-control])').forEach(audio => {
  audio.dataset.playControl = 'true';
  const name = audio.getAttribute('aria-label') || 'Sound';
  audio.id = `sound-preview-${++soundControlId}`;
  const controls = document.createElement('div');
  controls.className = 'sound-controls';
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'sound-play';
  button.setAttribute('aria-controls', audio.id);
  const status = document.createElement('span');
  status.className = 'sound-status';
  status.setAttribute('role', 'status');
  const update = () => {
    const playing = !audio.paused && !audio.ended;
    button.textContent = playing ? '■ Stop' : '▶ Play';
    button.setAttribute('aria-label', `${playing ? 'Stop' : 'Play'} ${name}`);
    button.setAttribute('aria-pressed', String(playing));
  };
  button.addEventListener('click', async () => {
    status.textContent = '';
    if (!audio.paused) {
      audio.pause();
      audio.currentTime = 0;
      return;
    }
    document.querySelectorAll('audio').forEach(other => {
      if (other !== audio) other.pause();
    });
    try {
      audio.currentTime = 0;
      await audio.play();
    } catch (error) {
      if (error.name !== 'AbortError') status.textContent = 'Could not play this sound. Check that its audio file is available.';
      update();
    }
  });
  ['play', 'pause', 'ended'].forEach(event => audio.addEventListener(event, update));
  audio.addEventListener('error', () => {
    status.textContent = 'This audio file could not be loaded.';
    update();
  });
  controls.append(button, status);
  audio.before(controls);
  update();
});
}
attachSoundControls();
document.addEventListener('library-rendered', attachSoundControls);

document.getElementById('stop').addEventListener('click', () => {
  document.querySelectorAll('audio').forEach(audio => {
    audio.pause();
    if (audio.readyState > 0) audio.currentTime = 0;
  });
});
