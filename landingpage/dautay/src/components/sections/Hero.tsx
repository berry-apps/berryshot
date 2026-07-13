import React from 'react';
import { motion } from 'motion/react';
import { Button } from '../ui/Button';
import { StrawberryIcon } from '../ui/StrawberryIcon';

const FloatingStrawberry = ({
  delay,
  size,
  startX,
  startY,
}: {
  delay: number;
  size: number;
  startX: string;
  startY: string;
}) => (
  <motion.div
    className='absolute text-strawberry/10'
    initial={{ x: startX, y: startY, rotate: 0 }}
    animate={{
      y: [startY, `calc(${startY} - 100px)`, startY],
      x: [startX, `calc(${startX} + 50px)`, startX],
      rotate: [0, 180, 360],
    }}
    transition={{
      duration: 20 + Math.random() * 10,
      repeat: Infinity,
      ease: 'linear',
      delay: delay,
    }}
    style={{ width: size }}
  >
    <StrawberryIcon />
  </motion.div>
);

export const Hero = () => {
  return (
    <section className='relative w-full min-h-screen flex items-center justify-center overflow-hidden pt-20 snap-start'>
      {/* Floating Background Elements */}
      <div className='absolute inset-0 pointer-events-none overflow-hidden'>
        <FloatingStrawberry startX='10vw' startY='20vh' size={40} delay={0} />
        <FloatingStrawberry startX='80vw' startY='15vh' size={60} delay={2} />
        <FloatingStrawberry startX='25vw' startY='70vh' size={30} delay={5} />
        <FloatingStrawberry startX='75vw' startY='80vh' size={50} delay={1} />
        <FloatingStrawberry startX='50vw' startY='40vh' size={45} delay={3} />
        <FloatingStrawberry startX='90vw' startY='50vh' size={35} delay={4} />
      </div>

      <div className='relative z-10 text-center px-6 max-w-3xl mx-auto flex flex-col items-center'>
        <motion.div
           initial={{ scale: 0.8, opacity: 0 }}
           animate={{ scale: 1, opacity: 1 }}
           transition={{ duration: 1, ease: 'easeOut' }}
           className='flex items-end justify-center gap-3 mb-8 h-24'
         >
           <div className='w-3 h-3 rounded-full bg-leaf/40 mb-3' />
           <div className='w-5 h-5 rounded-full bg-leaf/60 mb-3' />
           <div className='w-8 h-8 rounded-full bg-leaf/80 mb-3' />
           <StrawberryIcon className='w-20 h-20 text-strawberry drop-shadow-md' />
         </motion.div>

         <motion.h1
           initial={{ y: 20, opacity: 0 }}
           animate={{ y: 0, opacity: 1 }}
           transition={{ duration: 0.8, delay: 0.2 }}
           className='text-4xl md:text-6xl font-bold text-gray-800 mb-6 tracking-tight'
         >
           Chào mừng đến với hành trình của 
           <span className='text-strawberry'> Dâu Tây</span>
         </motion.h1>

         <motion.p
           initial={{ y: 20, opacity: 0 }}
           animate={{ y: 0, opacity: 1 }}
           transition={{ duration: 0.8, delay: 0.4 }}
           className='text-lg md:text-xl text-gray-600 mb-10 leading-relaxed'
         >
           Nơi lưu giữ những khoảnh khắc ngọt ngào, những bước đi đầu đời và hành
           trình khôn lớn của cô con gái bé bỏng.
         </motion.p>

          <motion.div
            initial={{ y: 20, opacity: 0 }}
            animate={{ y: 0, opacity: 1 }}
            transition={{ duration: 0.8, delay: 0.6 }}
            className='flex flex-wrap items-center justify-center gap-4'
          >
            <Button
              onClick={() =>
                document
                  .getElementById('memories')
                  ?.scrollIntoView({ behavior: 'smooth' })
              }
            >
              Xem hành trình của con
            </Button>
            <Button
              variant='secondary'
              href='https://notex.work'
              target='_blank'
            >
              Bố Dâu Tây
            </Button>
          </motion.div>
        </div>
    </section>
  );
};
