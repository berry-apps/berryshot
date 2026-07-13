import React from 'react';

export const StrawberryIcon = ({ className }: { className?: string }) => (
  <svg
    viewBox='0 0 100 100'
    className={className}
    fill='none'
    xmlns='http://www.w3.org/2000/svg'
  >
    <path
      d='M50 95C50 95 15 70 15 40C15 20 28 15 40 15C46 15 50 20 50 20C50 20 54 15 60 15C72 15 85 20 85 40C85 70 50 95 50 95Z'
      fill='currentColor'
    />
    <path
      d='M50 20C50 20 45 5 35 5C25 5 20 15 20 15C20 15 30 18 35 25C40 32 50 20 50 20Z'
      fill='var(--color-leaf)'
    />
    <path
      d='M50 20C50 20 55 5 65 5C75 5 80 15 80 15C80 15 70 18 65 25C60 32 50 20 50 20Z'
      fill='var(--color-leaf)'
    />
    <circle cx='35' cy='40' r='2' fill='var(--color-cream)' />
    <circle cx='65' cy='40' r='2' fill='var(--color-cream)' />
    <circle cx='50' cy='55' r='2' fill='var(--color-cream)' />
    <circle cx='40' cy='65' r='2' fill='var(--color-cream)' />
    <circle cx='60' cy='65' r='2' fill='var(--color-cream)' />
    <circle cx='50' cy='80' r='2' fill='var(--color-cream)' />
    <circle cx='25' cy='50' r='2' fill='var(--color-cream)' />
    <circle cx='75' cy='50' r='2' fill='var(--color-cream)' />
  </svg>
);
