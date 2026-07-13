import React, { useState } from 'react';
import { motion } from 'motion/react';
import { SectionWrapper } from '../ui/SectionWrapper';
import { StrawberryIcon } from '../ui/StrawberryIcon';
import { BookTransition } from './BookTransition';

export const CTA = () => {
  const [isDiaryOpen, setIsDiaryOpen] = useState(false);

  return (
    <>
      <SectionWrapper className='text-center py-32'>
        <motion.div
          whileHover={{ scale: 1.01 }}
          transition={{ type: 'spring', stiffness: 400, damping: 20 }}
          className='inline-block w-full max-w-3xl'
        >
          <div className='bg-white p-12 md:p-16 rounded-[3rem] shadow-sm border border-beige/30 relative overflow-hidden'>
            <div className='absolute top-0 right-0 w-32 h-32 bg-strawberry/5 rounded-bl-full' />
            <div className='absolute bottom-0 left-0 w-24 h-24 bg-leaf/10 rounded-tr-full' />

            <div className='relative z-10'>
              <h2 className='text-3xl md:text-4xl font-bold text-gray-800 mb-4'>
                Mở cuốn nhật ký của Dâu Tây
              </h2>
              <p className='text-gray-600 mb-10 max-w-md mx-auto text-lg'>
                Nơi lưu giữ từng khoảnh khắc nhỏ trong hành trình lớn lên
              </p>

              <motion.button
                onClick={() => setIsDiaryOpen(true)}
                whileHover='hover'
                initial='initial'
                variants={{
                  initial: {
                    scale: 1,
                    boxShadow: '0px 4px 10px rgba(201, 74, 74, 0.1)',
                  },
                  hover: {
                    scale: 1.03,
                    boxShadow: '0px 15px 30px rgba(201, 74, 74, 0.25)',
                  },
                }}
                className='bg-strawberry text-white px-8 py-4 rounded-full font-semibold flex items-center justify-center mx-auto transition-colors duration-300'
              >
                <span className='text-lg'>Mở nhật ký</span>
                <motion.div
                  variants={{
                    initial: { width: 0, opacity: 0, marginLeft: 0 },
                    hover: { width: 24, opacity: 1, marginLeft: 8 },
                  }}
                  className='overflow-hidden flex items-center justify-center'
                >
                  <StrawberryIcon className='w-6 h-6 text-white' />
                </motion.div>
              </motion.button>
            </div>
          </div>
        </motion.div>
      </SectionWrapper>

      <BookTransition
        isOpen={isDiaryOpen}
        onClose={() => setIsDiaryOpen(false)}
      />
    </>
  );
};
