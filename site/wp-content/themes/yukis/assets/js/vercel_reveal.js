(() => {
  const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const nodes = [...document.querySelectorAll('.vercel_reveal')];
  if (reduced || !('IntersectionObserver' in window)) return;

  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.remove('vercel_reveal_pending');
      entry.target.classList.add('vercel_reveal_visible');
      observer.unobserve(entry.target);
    }
  }, { threshold: 0.15 });

  for (const node of nodes) {
    const rect = node.getBoundingClientRect();
    if (rect.top < window.innerHeight && rect.bottom > 0) continue;
    node.classList.add('vercel_reveal_pending');
    observer.observe(node);
  }
})();
