import React from 'react';
import { Hero } from './components/sections/Hero';
import { MemoryPreview } from './components/sections/MemoryPreview';
import { Highlight } from './components/sections/Highlight';
import { TimelineSection } from './components/sections/TimelineSection';
import { CTA } from './components/sections/CTA';
import { Footer } from './components/sections/Footer';

export default function App() {
  return (
    <div className='h-screen overflow-y-auto overflow-x-hidden snap-y snap-mandatory scroll-smooth selection:bg-strawberry/20 selection:text-strawberry'>
      <Hero />
      <MemoryPreview />
      <Highlight />
      <TimelineSection />
      <CTA />
      <Footer />
    </div>
  );
}
