import React from "react";

export default function Loading({ size = 40, fullScreen = false }) {
  if (fullScreen) {
    return (
      <div className="page-centered-loading">
        <div className="loading-wrapper">
          <div className="shapes-5" style={{ width: size, height: size }} />
        </div>
        <style>{`
          .page-centered-loading {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 9999;
          }

          .loading-wrapper {
            display: flex;
            align-items: center;
            justify-content: center;
          }

          .shapes-5 {
            width: 40px;
            height: 40px;
            color: orange;
            background: linear-gradient(currentColor 0 0),
              linear-gradient(currentColor 0 0),
              linear-gradient(currentColor 0 0),
              linear-gradient(currentColor 0 0);
            background-size: 21px 21px;
            background-repeat: no-repeat;
            animation: sh5 1.5s infinite cubic-bezier(0.3, 1, 0, 1);
          }

          @keyframes sh5 {
            0% {
              background-position: 0 0, 100% 0, 100% 100%, 0 100%;
            }
            33% {
              background-position: 0 0, 100% 0, 100% 100%, 0 100%;
              width: 60px;
              height: 60px;
            }
            66% {
              background-position: 100% 0, 100% 100%, 0 100%, 0 0;
              width: 60px;
              height: 60px;
            }
            100% {
              background-position: 100% 0, 100% 100%, 0 100%, 0 0;
            }
          }
        `}</style>
      </div>
    );
  }

  return (
    <>
      <div className="loading-wrapper">
        <div className="shapes-5" style={{ width: size, height: size }} />
      </div>
      <style>{`
        .loading-wrapper {
          display: flex;
          align-items: center;
          justify-content: center;
        }

        .shapes-5 {
          width: 40px;
          height: 40px;
          color: orange;
          background: linear-gradient(currentColor 0 0),
            linear-gradient(currentColor 0 0), linear-gradient(currentColor 0 0),
            linear-gradient(currentColor 0 0);
          background-size: 21px 21px;
          background-repeat: no-repeat;
          animation: sh5 1.5s infinite cubic-bezier(0.3, 1, 0, 1);
        }

        @keyframes sh5 {
          0% {
            background-position: 0 0, 100% 0, 100% 100%, 0 100%;
          }
          33% {
            background-position: 0 0, 100% 0, 100% 100%, 0 100%;
            width: 60px;
            height: 60px;
          }
          66% {
            background-position: 100% 0, 100% 100%, 0 100%, 0 0;
            width: 60px;
            height: 60px;
          }
          100% {
            background-position: 100% 0, 100% 100%, 0 100%, 0 0;
          }
        }
      `}</style>
    </>
  );
}
