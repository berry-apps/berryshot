import React, { useState } from 'react';
import { motion } from 'motion/react';
import { SectionWrapper } from '../ui/SectionWrapper';
import { StrawberryIcon } from '../ui/StrawberryIcon';
import { milestones } from '../../data/milestones';

export const TimelineSection = () => {
  const [active, setActive] = useState<number | null>(null);

  return (
    <SectionWrapper id='timeline' className='bg-white/40 rounded-3xl'>
      <div className='text-center mb-16'>
        <h2 className='text-3xl font-bold text-gray-800 mb-4'>
          Hành trình khôn lớn
        </h2>
        <p className='text-gray-600 max-w-2xl mx-auto'>
          Từng cột mốc nhỏ bé nhưng vô cùng ý nghĩa trong cuộc đời của con.
        </p>
      </div>

      <div className='relative w-full py-10 overflow-x-auto hide-scrollbar'>
        <div className='min-w-[800px] flex items-center justify-between relative px-12'>
          {/* Connecting line */}
          <div className='absolute left-24 right-24 h-1 bg-gradient-to-r from-beige/30 via-beige to-beige/30 top-1/2 -translate-y-1/2 z-0 rounded-full' />

          {milestones.map((m, i) => (
            <div
              key={i}
              className='relative z-10 flex flex-col items-center group cursor-pointer w-32'
              onClick={() => setActive(i === active ? null : i)}
            >
              <div className='h-16 flex items-end pb-4 w-full justify-center'>
                <motion.div
                  className='opacity-0 group-hover:opacity-100 transition-opacity'
                  animate={{ opacity: active === i ? 1 : undefined }}
                >
                  <div className='bg-white px-4 py-2 rounded-2xl shadow-sm text-sm whitespace-nowrap text-strawberry font-medium border border-strawberry/10'>
                    {m.desc}
                  </div>
                </motion.div>
              </div>

              <div className='h-16 flex items-center justify-center'>
                <motion.div
                  whileHover={{ scale: 1.2 }}
                  className={`flex items-center justify-center rounded-full bg-cream border-4 border-white shadow-sm transition-colors ${active === i ? 'border-strawberry/40' : ''}`}
                  style={{ width: m.size + 24, height: m.size + 24 }}
                >
                  {m.isStrawberry ? (
                    <StrawberryIcon className='w-full h-full text-strawberry drop-shadow-sm p-1.5' />
                  ) : (
                    <div
                      className='bg-leaf rounded-full'
                      style={{ width: m.size, height: m.size }}
                    />
                  )}
                </motion.div>
              </div>

              <div className='h-16 flex items-start pt-4 w-full justify-center'>
                <p className='font-semibold text-gray-700 whitespace-nowrap'>
                  {m.age}
                </p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </SectionWrapper>
  );
};
