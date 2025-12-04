import { useEffect, useState } from "react";

export default function NotFound() {
  const [flashMessage, setFlashMessage] = useState("");

  useEffect(() => {
    setFlashMessage("Cannot connect to the server");
  }, []);

  const handleGoBack = () => {
    if (window.history.length > 1) window.history.back();
    else window.location.href = "/";
  };

  const handleReload = () => {
    window.location.reload();
  };

  const handleGoHome = () => {
    window.location.href = "/";
  };

  return (
    <section className="flex items-center justify-center min-h-screen bg-white p-6">
      <div className="w-full max-w-4xl bg-white rounded-2xl p-8 text-center">
        {flashMessage && (
          <div className="mb-8 p-4 rounded-lg bg-red-50 border border-red-200">
            <p className="text-red-800 font-medium">{flashMessage}</p>
          </div>
        )}
        <div className="flex flex-col items-center mb-12">
          <h1 className="text-9xl font-extrabold text-orange-600 leading-none">
            404
          </h1>
          <p className="text-xl text-gray-700 mt-4">
            The page you are looking for does not exist
          </p>
        </div>
        <div
          className="w-full h-[420px] bg-center bg-contain bg-no-repeat rounded-lg mb-10"
          style={{
            backgroundImage:
              "url('https://cdn.dribbble.com/users/285475/screenshots/2083086/dribbble_1.gif')",
          }}
        />
        <div className="flex flex-wrap items-center justify-center gap-3">
          <button
            onClick={handleGoHome}
            className="px-5 py-2.5 bg-green-600 text-white rounded-lg hover:bg-green-700 transition"
          >
            Home
          </button>
          <button
            onClick={handleGoBack}
            className="px-5 py-2.5 bg-gray-600 text-white rounded-lg hover:bg-gray-700 transition"
          >
            Go Back
          </button>
          <button
            onClick={handleReload}
            className="px-5 py-2.5 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition"
          >
            Reload
          </button>
        </div>
        <p className="text-sm text-gray-400 mt-6">
          URL:{" "}
          <code className="px-2 py-1 rounded bg-gray-100 border text-gray-700">
            {window.location.pathname}
          </code>
        </p>
      </div>
    </section>
  );
}
