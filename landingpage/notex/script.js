document.addEventListener("DOMContentLoaded", () => {
    
    // Register GSAP ScrollTrigger
    gsap.registerPlugin(ScrollTrigger);

    /* ========================================================
       1. Three.js Max Level 3D Particle Universe
    ======================================================== */
    const canvas = document.getElementById('webgl-canvas');
    const scene = new THREE.Scene();
    // Add subtle fog for depth
    scene.fog = new THREE.FogExp2(0x020202, 0.001);

    const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
    camera.position.z = 100;

    const renderer = new THREE.WebGLRenderer({ canvas, alpha: true, antialias: true });
    renderer.setSize(window.innerWidth, window.innerHeight);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));

    // Particle System Geometry
    const particlesGeometry = new THREE.BufferGeometry();
    const particlesCount = 5000;
    const posArray = new Float32Array(particlesCount * 3);
    const colorsArray = new Float32Array(particlesCount * 3);
    
    const color1 = new THREE.Color(0x00f0ff); // Neon Cyan
    const color2 = new THREE.Color(0x9d00ff); // Neon Purple

    for(let i = 0; i < particlesCount * 3; i+=3) {
        // Random spread in a massive sphere
        const r = 300 * Math.cbrt(Math.random());
        const theta = Math.random() * 2 * Math.PI;
        const phi = Math.acos(2 * Math.random() - 1);
        
        posArray[i] = r * Math.sin(phi) * Math.cos(theta); // x
        posArray[i+1] = r * Math.sin(phi) * Math.sin(theta); // y
        posArray[i+2] = r * Math.cos(phi); // z

        // Interpolate colors based on position
        const mixedColor = color1.clone().lerp(color2, Math.random());
        colorsArray[i] = mixedColor.r;
        colorsArray[i+1] = mixedColor.g;
        colorsArray[i+2] = mixedColor.b;
    }

    particlesGeometry.setAttribute('position', new THREE.BufferAttribute(posArray, 3));
    particlesGeometry.setAttribute('color', new THREE.BufferAttribute(colorsArray, 3));

    // Material with additive blending for glowing effect
    const particlesMaterial = new THREE.PointsMaterial({
        size: 0.8,
        vertexColors: true,
        blending: THREE.AdditiveBlending,
        transparent: true,
        opacity: 0.8
    });

    const particlesMesh = new THREE.Points(particlesGeometry, particlesMaterial);
    scene.add(particlesMesh);

    // Mouse Interaction for 3D Camera Parallax
    let mouseX = 0;
    let mouseY = 0;
    let targetX = 0;
    let targetY = 0;
    const windowHalfX = window.innerWidth / 2;
    const windowHalfY = window.innerHeight / 2;

    document.addEventListener('mousemove', (event) => {
        mouseX = (event.clientX - windowHalfX);
        mouseY = (event.clientY - windowHalfY);
    });

    // Animation Loop
    const clock = new THREE.Clock();
    
    function animate() {
        const elapsedTime = clock.getElapsedTime();
        
        // Smooth camera follow mouse
        targetX = mouseX * 0.05;
        targetY = mouseY * 0.05;
        camera.position.x += (targetX - camera.position.x) * 0.02;
        camera.position.y += (-targetY - camera.position.y) * 0.02;
        camera.lookAt(scene.position);

        // Constant VERY slow rotation
        particlesMesh.rotation.y = elapsedTime * 0.01;
        particlesMesh.rotation.x = elapsedTime * 0.005;

        renderer.render(scene, camera);
        window.requestAnimationFrame(animate);
    }
    animate();

    // Handle Resize
    window.addEventListener('resize', () => {
        camera.aspect = window.innerWidth / window.innerHeight;
        camera.updateProjectionMatrix();
        renderer.setSize(window.innerWidth, window.innerHeight);
    });

    /* ========================================================
       2. GSAP Intro Animations (No Scroll)
    ======================================================== */
    
    gsap.from(".title-layer-back", { z: -300, y: -100, opacity: 0, duration: 1.5, ease: "power3.out" });
    gsap.from(".title-layer-front", { z: 200, y: 150, filter: "blur(10px)", opacity: 0, duration: 1.5, ease: "power3.out" });
    gsap.from(".hero-subtitle", { y: -50, opacity: 0, duration: 1.5, ease: "power3.out", delay: 0.2 });
    gsap.from(camera.position, { z: 200, duration: 2, ease: "power2.out" });

    // Staggered 3D Card Reveal on load
    const cards = gsap.utils.toArray('.holo-card');
    gsap.from(cards, {
        y: 100,
        rotationX: 30,
        z: -100,
        opacity: 0,
        stagger: 0.2,
        duration: 1.5,
        ease: "power3.out",
        delay: 0.5
    });

    // Reveal Info Sections on scroll
    const infoSections = gsap.utils.toArray('.info-container');
    infoSections.forEach(section => {
        gsap.from(section, {
            scrollTrigger: {
                trigger: section,
                start: "top 85%",
            },
            y: 100,
            opacity: 0,
            duration: 1.2,
            ease: "power3.out"
        });
    });

    /* ========================================================
       3. 3D Hover Tilt Logic for Holo-Cards
    ======================================================== */
    cards.forEach(card => {
        card.addEventListener('mousemove', (e) => {
            const rect = card.getBoundingClientRect();
            const x = e.clientX - rect.left;
            const y = e.clientY - rect.top;
            
            const centerX = rect.width / 2;
            const centerY = rect.height / 2;
            const rotateX = ((y - centerY) / centerY) * -5; // Reduced to 5 deg
            const rotateY = ((x - centerX) / centerX) * 5;
            
            gsap.to(card, {
                rotationX: rotateX,
                rotationY: rotateY,
                transformPerspective: 1000,
                ease: "power2.out",
                duration: 0.5
            });
        });

        card.addEventListener('mouseleave', () => {
            gsap.to(card, {
                rotationX: 0,
                rotationY: 0,
                ease: "elastic.out(1, 0.3)",
                duration: 1.5
            });
        });
    });

});
