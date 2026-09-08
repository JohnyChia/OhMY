/**
 * iOS 18 Nova Orb Renderer (Canvas Dynamic Plasma Particle Shader)
 */
class NovaOrb {
  constructor(canvasId) {
    this.canvas = document.getElementById(canvasId);
    if (!this.canvas) return;
    this.ctx = this.canvas.getContext('2d');
    this.width = this.canvas.width;
    this.height = this.canvas.height;
    this.centerX = this.width / 2;
    this.centerY = this.height / 2;
    this.radius = this.width * 0.38;

    this.state = 'idle'; // idle, listening, thinking, speaking
    this.time = 0;
    this.audioVolume = 0;

    this.particles = [];
    this.initParticles();
    this.animate();
  }

  initParticles() {
    const count = 35;
    for (let i = 0; i < count; i++) {
      this.particles.push({
        angle: (i / count) * Math.PI * 2,
        speed: 0.005 + Math.random() * 0.015,
        offset: Math.random() * Math.PI * 2,
        radiusMult: 0.8 + Math.random() * 0.4,
        size: 20 + Math.random() * 40,
        color: this.getRandomNovaColor()
      });
    }
  }

  getRandomNovaColor() {
    const colors = [
      'rgba(0, 242, 254, ',    // Cyan
      'rgba(79, 172, 254, ',   // Electric Blue
      'rgba(127, 0, 255, ',    // Purple
      'rgba(225, 0, 255, ',    // Magenta
      'rgba(255, 8, 68, '      // Pink
    ];
    return colors[Math.floor(Math.random() * colors.length)];
  }

  setState(newState) {
    this.state = newState;
  }

  setAudioVolume(vol) {
    this.audioVolume = vol; // 0.0 to 1.0
  }

  animate() {
    requestAnimationFrame(() => this.animate());
    this.time += 0.035;

    this.ctx.clearRect(0, 0, this.width, this.height);

    // Calculate dynamic state intensity
    let speedMult = 1.0;
    let pulseScale = 1.0;

    if (this.state === 'listening') {
      speedMult = 2.2;
      pulseScale = 1.05 + this.audioVolume * 0.35 + Math.sin(this.time * 6) * 0.05;
    } else if (this.state === 'thinking') {
      speedMult = 3.5;
      pulseScale = 1.08 + Math.sin(this.time * 10) * 0.08;
    } else if (this.state === 'speaking') {
      speedMult = 2.0;
      pulseScale = 1.0 + Math.sin(this.time * 8) * 0.12;
    } else {
      // Idle
      pulseScale = 1.0 + Math.sin(this.time * 2) * 0.03;
    }

    const currentRadius = this.radius * pulseScale;

    // Draw background blur aura
    const glowGrad = this.ctx.createRadialGradient(
      this.centerX, this.centerY, currentRadius * 0.2,
      this.centerX, this.centerY, currentRadius * 1.4
    );
    glowGrad.addColorStop(0, 'rgba(0, 242, 254, 0.45)');
    glowGrad.addColorStop(0.4, 'rgba(225, 0, 255, 0.35)');
    glowGrad.addColorStop(0.7, 'rgba(127, 0, 255, 0.2)');
    glowGrad.addColorStop(1, 'rgba(0, 0, 0, 0)');

    this.ctx.fillStyle = glowGrad;
    this.ctx.beginPath();
    this.ctx.arc(this.centerX, this.centerY, currentRadius * 1.4, 0, Math.PI * 2);
    this.ctx.fill();

    // Composite Mode for fluid glowing lights
    this.ctx.globalCompositeOperation = 'screen';

    // Render fluid plasma blobs
    this.particles.forEach((p, idx) => {
      p.angle += p.speed * speedMult;
      const wave = Math.sin(this.time * 2 + p.offset) * 0.15;
      const r = currentRadius * (p.radiusMult + wave);

      const x = this.centerX + Math.cos(p.angle) * (r * 0.4);
      const y = this.centerY + Math.sin(p.angle + this.time * 0.5) * (r * 0.4);

      const blobGrad = this.ctx.createRadialGradient(x, y, 0, x, y, p.size * (currentRadius / 100));
      blobGrad.addColorStop(0, p.color + '0.75)');
      blobGrad.addColorStop(0.6, p.color + '0.25)');
      blobGrad.addColorStop(1, p.color + '0)');

      this.ctx.fillStyle = blobGrad;
      this.ctx.beginPath();
      this.ctx.arc(x, y, p.size * (currentRadius / 100), 0, Math.PI * 2);
      this.ctx.fill();
    });

    // Draw core bright Nova center sphere
    this.ctx.globalCompositeOperation = 'source-over';

    const coreGrad = this.ctx.createRadialGradient(
      this.centerX - currentRadius * 0.15,
      this.centerY - currentRadius * 0.15,
      currentRadius * 0.05,
      this.centerX, this.centerY, currentRadius * 0.85
    );
    coreGrad.addColorStop(0, 'rgba(255, 255, 255, 0.95)');
    coreGrad.addColorStop(0.25, 'rgba(165, 243, 252, 0.8)');
    coreGrad.addColorStop(0.65, 'rgba(192, 132, 252, 0.5)');
    coreGrad.addColorStop(1, 'rgba(15, 23, 42, 0.2)');

    this.ctx.fillStyle = coreGrad;
    this.ctx.beginPath();
    this.ctx.arc(this.centerX, this.centerY, currentRadius * 0.75, 0, Math.PI * 2);
    this.ctx.fill();
  }
}
