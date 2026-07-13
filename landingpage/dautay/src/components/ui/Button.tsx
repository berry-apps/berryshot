import React from 'react';

export interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary';
  children: React.ReactNode;
  href?: string;
  target?: string;
  rel?: string;
}

export const Button = ({
  variant = 'primary',
  children,
  className,
  href,
  target,
  rel,
  ...props
}: ButtonProps) => {
  const baseClass =
    'px-8 py-3.5 rounded-full font-semibold transition-all duration-300 ease-out flex items-center justify-center gap-2 tracking-wide cursor-pointer';
  const variants = {
    primary:
      'bg-strawberry text-white hover:bg-[#b33e3e] hover:shadow-lg hover:-translate-y-1',
    secondary:
      'bg-white text-strawberry border border-strawberry/20 hover:bg-strawberry/5 hover:shadow hover:-translate-y-0.5',
  };

  const combinedClasses = `${baseClass} ${variants[variant]} ${className || ''}`;

  if (href) {
    return (
      <a 
        href={href} 
        target={target} 
        rel={target === '_blank' ? 'noopener noreferrer' : rel} 
        className={combinedClasses}
      >
        {children}
      </a>
    );
  }

  return (
    <button
      className={combinedClasses}
      {...props}
    >
      {children}
    </button>
  );
};
