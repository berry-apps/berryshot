import React from 'react';
import { Heart } from 'lucide-react';

export const Footer = () => (
  <footer className='py-12 text-center border-t border-beige/50 mt-12 bg-white/30 snap-end px-6'>
    <div className='max-w-xl mx-auto'>
      <p className='text-gray-500 flex items-center justify-center gap-2 mb-4'>
        Made with <Heart className='w-4 h-4 text-strawberry fill-strawberry' />{' '}
        for Dâu Tây
      </p>
      
      <div className='flex flex-col md:flex-row items-center justify-center gap-3 md:gap-6 text-sm text-gray-400'>
        <p>© {new Date().getFullYear()} dautay.dev</p>
        <span className='hidden md:inline w-1 h-1 rounded-full bg-beige' />
        <a 
          href="https://notex.work" 
          target="_blank" 
          rel="noopener noreferrer"
          className='hover:text-strawberry transition-colors flex items-center gap-1 group'
        >
          <span className='group-hover:underline'>Bố Dâu Tây</span>
          <span className='text-[10px] opacity-70'>↗</span>
        </a>
      </div>
    </div>
  </footer>
);
