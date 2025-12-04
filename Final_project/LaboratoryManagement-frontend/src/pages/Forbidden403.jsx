export default function Forbidden403() {
  return (
    <div>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;900&display=swap');

        .paper-sad {
          transform: rotate(15deg);
          transition: transform 0.3s ease-in-out;
        }
        .paper-sad:hover {
          transform: rotate(25deg) translateY(-10px);
        }

        body {
          font-family: 'Inter', sans-serif;
        }
      `}</style>

      <div className="bg-sky-100 dark:bg-slate-900 font-['Inter'] flex items-center justify-center min-h-screen p-4 antialiased">
        <main className="w-full max-w-2xl mx-auto">
          <div className="bg-white dark:bg-slate-800 shadow-xl rounded-lg overflow-hidden">
            {/* Browser Header */}
            <div className="bg-blue-600 px-4 py-2 flex items-center">
              <div className="flex space-x-2">
                <div className="w-3 h-3 bg-white/40 rounded-full"></div>
                <div className="w-3 h-3 bg-white/40 rounded-full"></div>
                <div className="w-3 h-3 bg-white/40 rounded-full"></div>
              </div>
            </div>

            {/* Content Area */}
            <div className="relative p-8 sm:p-16 text-center">
              {/* Sad Paper Illustration */}
              <div className="absolute bottom-4 right-4 sm:bottom-8 sm:right-8 paper-sad z-0">
                <svg
                  className="w-24 h-28 sm:w-32 sm:h-36 text-slate-300 dark:text-slate-600"
                  fill="none"
                  height="144"
                  viewBox="0 0 80 96"
                  width="128"
                  xmlns="http://www.w3.org/2000/svg"
                >
                  {/* Paper body */}
                  <path d="M0 0H56L80 24V96H0V0Z" fill="currentColor" />

                  {/* Folded corner */}
                  <path d="M56 0L80 24H56V0Z" fill="black" fillOpacity="0.3" />

                  {/* Left eyebrow (sad) */}
                  <path
                    className="dark:stroke-slate-400"
                    d="M30 52C30 52 28 56 24 56C20 56 18 52 18 52"
                    stroke="#1E293B"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2.5"
                  />

                  {/* Right eyebrow (sad) */}
                  <path
                    className="dark:stroke-slate-400"
                    d="M62 52C62 52 60 56 56 56C52 56 50 52 50 52"
                    stroke="#1E293B"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2.5"
                  />

                  {/* Sad mouth */}
                  <path
                    className="dark:stroke-slate-400"
                    d="M38 72C38 72 40 68 44 68C48 68 50 72 50 72"
                    stroke="#1E293B"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth="2.5"
                  />

                  {/* Left eye */}
                  <circle
                    className="dark:fill-slate-400"
                    cx="27"
                    cy="65"
                    fill="#1E293B"
                    r="2"
                  />

                  {/* Right eye */}
                  <circle
                    className="dark:fill-slate-400"
                    cx="53"
                    cy="65"
                    fill="#1E293B"
                    r="2"
                  />
                </svg>
              </div>

              {/* Main Content */}
              <div className="relative z-10">
                <h1 className="text-7xl sm:text-9xl font-black text-slate-800 dark:text-slate-100 tracking-tighter">
                  403
                </h1>

                <p className="mt-4 text-xl sm:text-2xl font-medium text-slate-800 dark:text-slate-100">
                  Forbidden
                </p>

                <p className="mt-2 text-slate-500 dark:text-slate-400">
                  Sorry, you don't have permission to access this page.
                </p>

                <a
                  className="mt-8 inline-block bg-blue-600 text-white font-semibold px-6 py-3 rounded-lg shadow-lg hover:bg-opacity-90 focus:outline-none focus:ring-2 focus:ring-blue-600 focus:ring-offset-2 focus:ring-offset-white dark:focus:ring-offset-slate-800 transition-all cursor-pointer"
                  href="/"
                  onClick={(e) => {
                    e.preventDefault();
                    window.location.href = "/";
                  }}
                >
                  Go back home
                </a>
              </div>
            </div>
          </div>
        </main>
      </div>
    </div>
  );
}
