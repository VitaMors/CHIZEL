const canvas = document.getElementById("hero-model");
const ctx = canvas.getContext("2d");

const vertices = [
  [-1.3, -0.9, -1.0],
  [1.15, -0.9, -1.0],
  [1.25, 0.72, -0.9],
  [-1.05, 0.88, -1.0],
  [-1.1, -0.72, 1.0],
  [1.0, -0.74, 1.0],
  [0.82, 0.92, 0.95],
  [-0.95, 0.72, 1.0],
  [-0.38, -1.34, -0.28],
  [0.34, -1.3, -0.18],
];

const faces = [
  [0, 1, 2, 3, "#485156"],
  [4, 7, 6, 5, "#c9cfcb"],
  [0, 4, 5, 1, "#aeb5b1"],
  [3, 2, 6, 7, "#6f777b"],
  [1, 5, 6, 2, "#d9ded9"],
  [0, 3, 7, 4, "#90989b"],
  [0, 8, 9, 1, "#c67955"],
  [4, 5, 9, 8, "#e0b94d"],
  [0, 4, 8, "#6aa870"],
  [1, 9, 5, "#eef1ed"],
];

function resizeCanvas() {
  const ratio = window.devicePixelRatio || 1;
  const rect = canvas.getBoundingClientRect();
  canvas.width = Math.max(1, Math.floor(rect.width * ratio));
  canvas.height = Math.max(1, Math.floor(rect.height * ratio));
  ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
}

function rotate(point, time) {
  const yaw = time * 0.00034;
  const pitch = -0.42 + Math.sin(time * 0.00022) * 0.08;
  const [x, y, z] = point;
  const cy = Math.cos(yaw);
  const sy = Math.sin(yaw);
  const cp = Math.cos(pitch);
  const sp = Math.sin(pitch);
  const x1 = x * cy - z * sy;
  const z1 = x * sy + z * cy;
  const y1 = y * cp - z1 * sp;
  const z2 = y * sp + z1 * cp;
  return [x1, y1, z2];
}

function project(point, width, height) {
  const distance = 4.8;
  const scale = Math.min(width, height) * 0.32;
  const perspective = scale / (distance + point[2]);
  return [
    width * 0.52 + point[0] * perspective,
    height * 0.54 - point[1] * perspective,
    point[2],
  ];
}

function draw(time) {
  const width = canvas.clientWidth;
  const height = canvas.clientHeight;
  ctx.clearRect(0, 0, width, height);

  const transformed = vertices.map((vertex) => project(rotate(vertex, time), width, height));
  const sortedFaces = faces
    .map((face) => ({
      face,
      depth: face.slice(0, -1).reduce((sum, index) => sum + transformed[index][2], 0) / (face.length - 1),
    }))
    .sort((a, b) => b.depth - a.depth);

  ctx.save();
  ctx.shadowColor = "rgba(0,0,0,0.42)";
  ctx.shadowBlur = 28;
  ctx.shadowOffsetY = 24;
  ctx.fillStyle = "rgba(0,0,0,0.28)";
  ctx.beginPath();
  ctx.ellipse(width * 0.54, height * 0.78, width * 0.2, height * 0.045, 0, 0, Math.PI * 2);
  ctx.fill();
  ctx.restore();

  sortedFaces.forEach(({ face }) => {
    ctx.beginPath();
    face.slice(0, -1).forEach((index, pointIndex) => {
      const point = transformed[index];
      if (pointIndex === 0) {
        ctx.moveTo(point[0], point[1]);
      } else {
        ctx.lineTo(point[0], point[1]);
      }
    });
    ctx.closePath();
    ctx.fillStyle = face[face.length - 1];
    ctx.strokeStyle = "rgba(16,18,20,0.65)";
    ctx.lineWidth = 1.4;
    ctx.fill();
    ctx.stroke();
  });

  requestAnimationFrame(draw);
}

resizeCanvas();
window.addEventListener("resize", resizeCanvas);
requestAnimationFrame(draw);
