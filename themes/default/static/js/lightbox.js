(function() {
  const lb = document.getElementById('lightbox');
  if (!lb) return;
  const img = document.getElementById('lightbox-img');
  const exifEl = document.getElementById('lightbox-exif');
  document.querySelectorAll('.media-thumb').forEach(function(t) {
    t.addEventListener('click', function() {
      img.src = t.dataset.full;
      exifEl.textContent = t.dataset.exif || '';
      lb.style.display = 'flex';
    });
  });
  lb.addEventListener('click', function(e) {
    if (e.target === lb || e.target.classList.contains('lightbox-close')) {
      lb.style.display = 'none';
    }
  });
  document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') lb.style.display = 'none';
  });
})();