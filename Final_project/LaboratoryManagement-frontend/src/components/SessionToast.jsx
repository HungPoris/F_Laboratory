import React, { useEffect, useState, useRef } from "react";

const SessionToast = ({ isOpen, onClose }) => {
  const [countdown, setCountdown] = useState(60);
  const intervalRef = useRef(null);

  useEffect(() => {
    if (!isOpen) {
      setCountdown(60);
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
      return;
    }

    setCountdown(60);

    intervalRef.current = setInterval(() => {
      setCountdown((prev) => {
        if (prev <= 1) {
          if (intervalRef.current) {
            clearInterval(intervalRef.current);
            intervalRef.current = null;
          }
          return 0;
        }
        return prev - 1;
      });
    }, 1000);

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current);
        intervalRef.current = null;
      }
    };
  }, [isOpen]);

  if (!isOpen) return null;

  const isCountdownPhase = countdown <= 10;

  const handleReload = () => {
    window.location.reload();
  };

  const styles = {
    overlay: {
      position: "fixed",
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      backgroundColor: "rgba(0, 0, 0, 0.6)",
      display: "flex",
      alignItems: "flex-start",
      justifyContent: "center",
      paddingTop: "80px",
      zIndex: 9999,
      animation: "fadeIn 0.3s ease-in",
    },
    toast: {
      background: "white",
      borderRadius: "12px",
      padding: "24px",
      maxWidth: "500px",
      width: "90%",
      boxShadow: "0 10px 40px rgba(0, 0, 0, 0.3)",
      display: "flex",
      gap: "16px",
      alignItems: "flex-start",
      animation: isCountdownPhase
        ? "slideDown 0.4s ease-out, pulse 1s infinite"
        : "slideDown 0.4s ease-out",
      borderLeft: isCountdownPhase ? "4px solid #ef4444" : "4px solid #f59e0b",
    },
    icon: {
      flexShrink: 0,
    },
    content: {
      flex: 1,
      minWidth: 0,
    },
    title: {
      fontSize: "18px",
      fontWeight: 700,
      color: "#1f2937",
      margin: "0 0 8px 0",
    },
    message: {
      fontSize: "14px",
      color: "#4b5563",
      lineHeight: 1.5,
      margin: "0 0 12px 0",
    },
    countdownDisplay: {
      display: "flex",
      alignItems: "baseline",
      gap: "8px",
      marginTop: "12px",
      padding: "12px",
      background: "linear-gradient(135deg, #fef3c7, #fed7aa)",
      borderRadius: "8px",
    },
    countdownNumber: {
      fontSize: "32px",
      fontWeight: 800,
      color: "#b45309",
      lineHeight: 1,
    },
    countdownLabel: {
      fontSize: "14px",
      color: "#92400e",
      fontWeight: 600,
    },
    actions: {
      display: "flex",
      flexDirection: "column",
      gap: "8px",
      flexShrink: 0,
    },
    btnReload: {
      padding: "10px 20px",
      borderRadius: "8px",
      fontSize: "14px",
      fontWeight: 600,
      cursor: "pointer",
      border: "none",
      background: "#3b82f6",
      color: "white",
      transition: "all 0.2s",
      whiteSpace: "nowrap",
    },
    btnClose: {
      padding: "8px 12px",
      borderRadius: "8px",
      fontSize: "18px",
      fontWeight: 600,
      cursor: "pointer",
      border: "none",
      background: "#f3f4f6",
      color: "#6b7280",
      transition: "all 0.2s",
      whiteSpace: "nowrap",
    },
  };

  return (
    <>
      <style>
        {`
          @keyframes fadeIn {
            from { opacity: 0; }
            to { opacity: 1; }
          }

          @keyframes slideDown {
            from {
              opacity: 0;
              transform: translateY(-30px);
            }
            to {
              opacity: 1;
              transform: translateY(0);
            }
          }

          @keyframes pulse {
            0%, 100% {
              box-shadow: 0 10px 40px rgba(0, 0, 0, 0.3);
            }
            50% {
              box-shadow: 0 10px 40px rgba(239, 68, 68, 0.4);
            }
          }

          .session-toast-btn-reload:hover {
            background: #2563eb !important;
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(59, 130, 246, 0.4);
          }

          .session-toast-btn-reload:active {
            transform: translateY(0);
          }

          .session-toast-btn-close:hover {
            background: #e5e7eb !important;
            color: #374151 !important;
          }

          @media (max-width: 640px) {
            .session-toast-container {
              flex-direction: column !important;
              padding: 20px !important;
            }

            .session-toast-actions {
              flex-direction: row !important;
              width: 100% !important;
            }

            .session-toast-btn-reload {
              flex: 1 !important;
            }

            .session-toast-btn-close {
              flex: 0 0 auto !important;
            }
          }
        `}
      </style>

      <div style={styles.overlay}>
        <div style={styles.toast} className="session-toast-container">
          <div style={styles.icon}>
            {isCountdownPhase ? (
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
                <circle
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="#ef4444"
                  strokeWidth="2"
                />
                <path
                  d="M12 6v6l4 2"
                  stroke="#ef4444"
                  strokeWidth="2"
                  strokeLinecap="round"
                />
              </svg>
            ) : (
              <svg width="48" height="48" viewBox="0 0 24 24" fill="none">
                <circle
                  cx="12"
                  cy="12"
                  r="10"
                  stroke="#f59e0b"
                  strokeWidth="2"
                />
                <path
                  d="M12 7v6M12 16h.01"
                  stroke="#f59e0b"
                  strokeWidth="2"
                  strokeLinecap="round"
                />
              </svg>
            )}
          </div>

          <div style={styles.content}>
            <h3 style={styles.title}>
              {isCountdownPhase
                ? "Session Expiring Soon!"
                : "Session About to Expire"}
            </h3>
            <p style={styles.message}>
              {isCountdownPhase
                ? `Your session will expire in ${countdown} second${
                    countdown !== 1 ? "s" : ""
                  }. Please reload the page to continue.`
                : "Your session will expire in less than 1 minute. Please reload the page to stay logged in."}
            </p>
            {isCountdownPhase && (
              <div style={styles.countdownDisplay}>
                <span style={styles.countdownNumber}>{countdown}</span>
                <span style={styles.countdownLabel}>seconds</span>
              </div>
            )}
          </div>

          <div style={styles.actions} className="session-toast-actions">
            <button
              style={styles.btnReload}
              className="session-toast-btn-reload"
              onClick={handleReload}
            >
              🔄 Reload Page
            </button>
            <button
              style={styles.btnClose}
              className="session-toast-btn-close"
              onClick={onClose}
            >
              ✕
            </button>
          </div>
        </div>
      </div>
    </>
  );
};

export default SessionToast;
