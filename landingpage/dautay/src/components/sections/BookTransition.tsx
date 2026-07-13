import React, { useState } from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { ChevronLeft, ChevronRight } from 'lucide-react';
import { StrawberryIcon } from '../ui/StrawberryIcon';
import { diaryPages } from '../../data/diary';

export const BookTransition = ({
  isOpen,
  onClose,
}: {
  isOpen: boolean;
  onClose: () => void;
}) => {
  const [currentPage, setCurrentPage] = useState(0);
  const [isMobile, setIsMobile] = useState(false);

  React.useEffect(() => {
    const handleResize = () => setIsMobile(window.innerWidth < 768);
    handleResize();
    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  React.useEffect(() => {
    if (!isOpen) {
      setTimeout(() => setCurrentPage(0), 500);
    }
  }, [isOpen]);

  const page = diaryPages[currentPage];

  const handleNext = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (currentPage < diaryPages.length - 1) setCurrentPage((c) => c + 1);
  };

  const handlePrev = (e: React.MouseEvent) => {
    e.stopPropagation();
    if (currentPage > 0) setCurrentPage((c) => c - 1);
  };

  return (
    <AnimatePresence>
      {isOpen && (
        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0 }}
          className='fixed inset-0 z-50 flex items-center justify-center bg-cream/95 backdrop-blur-sm p-4'
          onClick={onClose}
        >
          {isMobile ? (
            <div
              className='relative w-full max-w-sm h-[85vh] bg-[#FDFBF7] rounded-[2rem] shadow-2xl flex flex-col overflow-hidden'
              onClick={(e) => e.stopPropagation()}
            >
              {/* Top Half: Media */}
              <div className='relative h-[45%] bg-black/5'>
                <AnimatePresence mode='wait'>
                  <motion.div
                    key={`mobile-media-${page.id}`}
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.4 }}
                    className='w-full h-full flex items-center justify-center'
                  >
                    {page.type === 'video' ? (
                      <video
                        src={page.media}
                        className='absolute inset-0 w-full h-full object-cover'
                        autoPlay
                        loop
                        muted
                        playsInline
                      />
                    ) : (
                      <img
                        src={page.media}
                        className='absolute inset-0 w-full h-full object-cover'
                        alt={page.title}
                      />
                    )}
                  </motion.div>
                </AnimatePresence>
                
                {/* Close Button overlay */}
                <button
                  onClick={onClose}
                  className='absolute top-4 right-4 z-20 w-8 h-8 bg-black/30 backdrop-blur-sm text-white rounded-full flex items-center justify-center'
                >
                  <span className='sr-only'>Đóng</span>
                  <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor"><path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" /></svg>
                </button>
              </div>

              {/* Bottom Half: Diary Text (Notebook style) */}
              <div className='relative flex-1 bg-[#FDFBF7] flex flex-col'>
                {/* Notebook Lines Background */}
                <div
                  className='absolute inset-0 pointer-events-none'
                  style={{
                    backgroundImage:
                      'repeating-linear-gradient(transparent, transparent 31px, rgba(169, 194, 155, 0.4) 31px, rgba(169, 194, 155, 0.4) 32px)',
                    backgroundPositionY: '8px',
                  }}
                />
                
                {/* Vertical red margin line typical of notebooks */}
                <div className='absolute left-8 top-0 bottom-0 w-[2px] bg-strawberry/30 pointer-events-none' />

                <div className="relative z-10 flex-1 overflow-y-auto px-6 py-8 pl-14">
                  <AnimatePresence mode="wait">
                    <motion.div
                      key={`mobile-text-${page.id}`}
                      initial={{ opacity: 0, y: 10 }}
                      animate={{ opacity: 1, y: 0 }}
                      exit={{ opacity: 0, y: -10 }}
                      transition={{ duration: 0.4 }}
                      style={{ fontFamily: 'var(--font-handwriting)' }}
                    >
                      <div className='flex justify-between items-end mb-6 border-b-2 border-dashed border-beige/50 pb-2 flex-wrap'>
                        <h3 className='text-2xl font-bold text-strawberry mb-1 w-full'>
                          {page.title}
                        </h3>
                        <span className='text-gray-500 text-xs'>{page.date}</span>
                      </div>

                      <div className='text-gray-700 leading-8 text-base overflow-hidden'>
                        {page.paragraphs.map((text, idx) => (
                          <p key={idx} className='mb-6'>
                            {text}
                          </p>
                        ))}
                      </div>

                      <div className='text-right text-gray-600 font-medium text-lg mt-6 pb-24'>
                        {page.signature}
                      </div>
                    </motion.div>
                  </AnimatePresence>
                </div>

                {/* Mobile Pagination Controls */}
                <div className='absolute bottom-6 left-0 right-0 flex justify-center gap-6 z-20 pointer-events-auto'>
                  <button
                    onClick={handlePrev}
                    disabled={currentPage === 0}
                    className={`w-12 h-12 rounded-full flex items-center justify-center shadow-md backdrop-blur-sm transition-colors ${currentPage === 0 ? 'bg-white/50 text-gray-400' : 'bg-white/90 text-strawberry hover:bg-white'}`}
                  >
                    <ChevronLeft className='w-6 h-6' />
                  </button>
                  <button
                    onClick={handleNext}
                    disabled={currentPage === diaryPages.length - 1}
                    className={`w-12 h-12 rounded-full flex items-center justify-center shadow-md backdrop-blur-sm transition-colors ${currentPage === diaryPages.length - 1 ? 'bg-white/50 text-gray-400' : 'bg-white/90 text-strawberry hover:bg-white'}`}
                  >
                    <ChevronRight className='w-6 h-6' />
                  </button>
                </div>
              </div>
            </div>
          ) : (
          <div
            className='relative w-[90vw] max-w-5xl h-[65vh] md:h-[75vh]'
            style={{ perspective: '2500px' }}
          >
            {/* Right Page (Static background) */}
            <div className='absolute right-0 w-1/2 h-full bg-[#FDFBF7] rounded-r-2xl shadow-xl flex flex-col items-center justify-center p-8 md:p-12 border-l border-beige/40'>
              <motion.div
                initial={{ opacity: 0, y: 10 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 1.2, duration: 0.8 }}
                className='text-center'
              >
                <StrawberryIcon className='w-10 h-10 text-strawberry/30 mx-auto mb-6' />
                <h3 className='text-xl md:text-2xl font-bold text-gray-800 mb-4 font-serif'>
                  Trang đầu tiên...
                </h3>
                <p className='text-gray-600 leading-relaxed text-sm md:text-base'>
                  "Chào con gái bé bỏng. Cuốn nhật ký này là dành cho con, để
                  mai này lớn lên, con sẽ biết mình đã được yêu thương nhiều đến
                  nhường nào..."
                </p>
              </motion.div>
            </div>

            {/* Left Page (Media, revealed after cover opens) */}
            <div className='absolute left-0 w-1/2 h-full bg-[#FDFBF7] rounded-l-2xl shadow-xl flex items-center justify-center p-6 md:p-10'>
              <AnimatePresence mode="wait">
                <motion.div
                  key={`media-${page.id}`}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  transition={{ duration: 0.4 }}
                  className='w-full h-full rounded-xl overflow-hidden bg-black/5 shadow-inner relative flex items-center justify-center'
                >
                  {page.type === 'video' ? (
                    <video
                      src={page.media}
                      className='absolute inset-0 w-full h-full object-cover'
                      autoPlay
                      loop
                      muted
                      playsInline
                    />
                  ) : (
                    <img
                      src={page.media}
                      className='absolute inset-0 w-full h-full object-cover'
                      alt={page.title}
                    />
                  )}
                </motion.div>
              </AnimatePresence>

              {/* Prev Button Overlay */}
              {currentPage > 0 && (
                <button
                  onClick={handlePrev}
                  className='absolute left-10 md:left-14 top-1/2 -translate-y-1/2 w-12 h-12 bg-white/50 hover:bg-white/90 backdrop-blur-sm shadow-md rounded-full flex items-center justify-center transition-colors z-20'
                >
                  <ChevronLeft className='w-8 h-8 text-gray-800' />
                </button>
              )}
            </div>

            {/* Cover Page (Flips open) */}
            <motion.div
              initial={{ rotateY: 0 }}
              animate={{ rotateY: -180 }}
              transition={{
                duration: 1.8,
                ease: [0.64, 0.04, 0.35, 1],
                delay: 0.3,
              }}
              style={{
                transformOrigin: 'right center',
                transformStyle: 'preserve-3d',
              }}
              className='absolute left-0 w-1/2 h-full z-10'
            >
              {/* Front of Cover */}
              <div
                className='absolute inset-0 bg-strawberry rounded-l-2xl shadow-2xl flex flex-col items-center justify-center border-r border-black/20'
                style={{ backfaceVisibility: 'hidden' }}
              >
                <div className='w-[calc(100%-24px)] h-[calc(100%-24px)] border-[2px] border-white/20 rounded-l-xl flex flex-col items-center justify-center p-4 md:p-8'>
                  <StrawberryIcon className='w-16 h-16 md:w-20 md:h-20 text-white mb-6 drop-shadow-md' />
                  <h2 className='text-3xl md:text-4xl font-bold text-white text-center tracking-wide drop-shadow-md'>
                    Nhật ký
                    <br />
                    Dâu Tây
                  </h2>
                </div>
              </div>

              {/* Back of Cover (Inside left page / revealed on right after opening) */}
              <div
                className='absolute inset-0 bg-[#FDFBF7] rounded-r-2xl shadow-inner border-l border-black/5 overflow-hidden flex flex-col'
                style={{
                  transform: 'rotateY(180deg)',
                  backfaceVisibility: 'hidden',
                }}
              >
                {/* Notebook Lines Background */}
                <div
                  className='absolute inset-0 pointer-events-none'
                  style={{
                    backgroundImage:
                      'repeating-linear-gradient(transparent, transparent 31px, rgba(169, 194, 155, 0.4) 31px, rgba(169, 194, 155, 0.4) 32px)',
                    backgroundPositionY: '16px',
                  }}
                />

                {/* Vertical red margin line typical of notebooks */}
                <div className='absolute left-10 md:left-14 top-0 bottom-0 w-[2px] bg-strawberry/30 pointer-events-none' />

                <div className="relative z-10 h-full p-8 md:p-12 pl-14 md:pl-20">
                  <AnimatePresence mode="wait">
                    <motion.div
                      key={`text-${page.id}`}
                      initial={{ opacity: 0, x: 10 }}
                      animate={{ opacity: 1, x: 0 }}
                      exit={{ opacity: 0, x: -10 }}
                      transition={{ duration: 0.4, delay: currentPage === 0 ? 1.5 : 0 }}
                      className='h-full flex flex-col'
                      style={{ fontFamily: 'var(--font-handwriting)' }}
                    >
                      <div className='flex justify-between items-end mb-[32px] border-b-2 border-dashed border-beige/50 pb-2 flex-wrap'>
                        <h3 className='text-3xl font-bold text-strawberry mb-2 md:mb-0'>
                          {page.title}
                        </h3>
                        <span className='text-gray-500 text-sm whitespace-nowrap'>{page.date}</span>
                      </div>

                      <div className='text-gray-700 leading-[32px] text-lg lg:text-xl flex-1'>
                        {page.paragraphs.map((text, idx) => (
                          <p key={idx} className='mb-[32px]'>
                            {text}
                          </p>
                        ))}
                      </div>

                      <div className='mt-auto text-right text-gray-600 font-medium text-xl'>
                        {page.signature}
                      </div>
                    </motion.div>
                  </AnimatePresence>
                </div>

                {/* Next Button Overlay */}
                {currentPage < diaryPages.length - 1 && (
                  <button
                    onClick={handleNext}
                    className='absolute right-10 md:right-14 top-1/2 -translate-y-1/2 w-12 h-12 bg-white/50 hover:bg-white/90 backdrop-blur-sm shadow-md rounded-full flex items-center justify-center transition-colors z-20'
                  >
                    <ChevronRight className='w-8 h-8 text-gray-800' />
                  </button>
                )}
              </div>
            </motion.div>
          </div>
          )}

          {!isMobile && (
            <motion.p
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              transition={{ delay: 2 }}
              className='absolute bottom-8 text-gray-500 text-sm tracking-widest uppercase cursor-pointer'
            >
              Nhấn ra ngoài để đóng
            </motion.p>
          )}
        </motion.div>
      )}
    </AnimatePresence>
  );
};
