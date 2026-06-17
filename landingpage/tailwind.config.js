/** @type {import('tailwindcss').Config} */
module.exports = {
  content: ["./*.html", "./**/*.html"],
  theme: {
    extend: {
      fontFamily: {
        sans: ['Inter', 'sans-serif'],
        display: ['Outfit', 'sans-serif'],
      },
      colors: {
        berry: {
          50: '#fff0f3',
          100: '#ffdde3',
          200: '#ffc0cb',
          300: '#ffa1b3',
          400: '#ff6b8b',
          500: '#ff2e5b', // Main strawberry red
          600: '#e01b47',
          700: '#bd1035',
          800: '#9c0d2a',
          950: '#0f0205',
        },
        fuchsiaAccent: {
          DEFAULT: '#d946ef',
        },
        darkBg: {
          DEFAULT: '#050208',
          card: '#0f0617',
          border: '#1f0d2c',
        }
      },
      animation: {
        'pulse-slow': 'pulse 8s cubic-bezier(0.4, 0, 0.6, 1) infinite',
        'float': 'float 6s ease-in-out infinite',
        'float-delayed': 'float 6s ease-in-out 3s infinite',
        'drift-slow': 'drift 20s linear infinite',
      },
      keyframes: {
        float: {
          '0%, 100%': { transform: 'translateY(0px)' },
          '50%': { transform: 'translateY(-12px)' },
        },
        drift: {
          '0%': { transform: 'rotate(0deg) translate(0px, 0px)' },
          '50%': { transform: 'rotate(180deg) translate(20px, 40px)' },
          '100%': { transform: 'rotate(360deg) translate(0px, 0px)' },
        }
      }
    }
  }
}
