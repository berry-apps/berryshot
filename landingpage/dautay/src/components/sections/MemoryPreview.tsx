import React from 'react';
import { motion } from 'motion/react';
import { ArrowRight } from 'lucide-react';
import { SectionWrapper } from '../ui/SectionWrapper';
import { Button } from '../ui/Button';
import { memories, Memory } from '../../data/memories';

const MemoryCard = ({ memory }: { memory: Memory }) => {
  return (
    <motion.div
      whileHover={{ scale: 1.02, y: -10, rotate: 0, zIndex: 10 }}
      transition={{ type: 'spring', stiffness: 300, damping: 20 }}
      className='bg-white p-4 pb-6 rounded-sm shadow-md border border-beige/50 relative'
      style={{ rotate: `${memory.rotation}deg` }}
    >
      {memory.image ? (
        <div className='w-full aspect-square rounded-sm mb-4 overflow-hidden relative'>
          <img
            src={memory.image}
            alt={memory.caption}
            className='w-full h-full object-cover'
          />
        </div>
      ) : (
        <div
          className={`w-full aspect-square rounded-sm mb-4 ${memory.gradient} opacity-80`}
        />
      )}
      <div className='text-center'>
        <p className='font-medium text-gray-700 text-lg'>{memory.caption}</p>
        <p className='text-sm text-gray-400 mt-1'>{memory.date}</p>
      </div>
    </motion.div>
  );
};

export const MemoryPreview = () => {
  return (
    <SectionWrapper id='memories'>
      <div className='flex flex-col md:flex-row justify-between items-end mb-12 gap-6'>
        <div>
          <h2 className='text-3xl font-bold text-gray-800 mb-4'>
            Ký ức ngọt ngào
          </h2>
          <p className='text-gray-600 max-w-xl'>
            Những khoảnh khắc đáng yêu được lưu giữ cẩn thận như một cuốn nhật
            ký số.
          </p>
        </div>
        <Button variant='secondary' className='shrink-0'>
          Xem tất cả <ArrowRight className='w-4 h-4' />
        </Button>
      </div>

      <div className='grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8 md:gap-12 px-4'>
        {memories.map((memory, index) => (
          <motion.div
            key={memory.id}
            initial={{ opacity: 0, y: 50 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true, margin: '-50px' }}
            transition={{ duration: 0.6, delay: index * 0.1 }}
          >
            <MemoryCard memory={memory} />
          </motion.div>
        ))}
      </div>
    </SectionWrapper>
  );
};
