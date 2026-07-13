import React from 'react';
import { motion } from 'motion/react';
import { Heart } from 'lucide-react';

export const Highlight = () => (
  <section className='relative w-full min-h-screen flex flex-col justify-center py-32 overflow-hidden bg-white/50 snap-start'>
    <div className='absolute top-0 left-0 w-full h-full overflow-hidden pointer-events-none'>
      <motion.div
        animate={{
          scale: [1, 1.1, 1],
          rotate: [0, 90, 0],
          x: [0, 50, 0],
          y: [0, -50, 0],
        }}
        transition={{ duration: 20, repeat: Infinity, ease: 'easeInOut' }}
        className='absolute -top-40 -right-40 w-96 h-96 bg-beige/60 rounded-full mix-blend-multiply filter blur-3xl opacity-70'
      />
      <motion.div
        animate={{
          scale: [1, 1.2, 1],
          rotate: [0, -90, 0],
          x: [0, -50, 0],
          y: [0, 50, 0],
        }}
        transition={{ duration: 25, repeat: Infinity, ease: 'easeInOut' }}
        className='absolute -bottom-40 -left-40 w-96 h-96 bg-strawberry/20 rounded-full mix-blend-multiply filter blur-3xl opacity-70'
      />
    </div>

    <div className='relative z-10 max-w-4xl mx-auto px-6 text-center'>
      <motion.div
        initial={{ opacity: 0, scale: 0.9 }}
        whileInView={{ opacity: 1, scale: 1 }}
        viewport={{ once: true }}
        transition={{ duration: 1 }}
      >
        <Heart className='w-12 h-12 text-strawberry/40 mx-auto mb-8' />
        <h2 className='text-3xl md:text-5xl font-medium text-gray-800 leading-tight mb-8'>
          "Mỗi ngày nhìn con lớn lên là một món quà tuyệt vời nhất mà bố mẹ có
          được."
        </h2>
        <p className='text-gray-500 font-medium tracking-widest uppercase text-sm'>
          — Ba & Mẹ —
        </p>
      </motion.div>
    </div>
  </section>
);
