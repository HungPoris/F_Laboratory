import React, { useState, useRef, useEffect } from "react";
import { X, Loader2, MoreVertical } from "lucide-react";
import Swal from "sweetalert2";
import axios from "axios";
import SockJS from "sockjs-client/dist/sockjs";
import Stomp from "stompjs";

import { useAuth } from "../lib/auth";

const API_BASE =
  import.meta.env.VITE_API_TESTORDER_PATIENT || "https://be2.flaboratory.cloud";

export default function CommentModal({
  open,
  onClose,
  itemId,
  itemType = "testOrder",
  onCommentAdded,
}) {
  const [comments, setComments] = useState([]);
  const [inputValue, setInputValue] = useState("");
  const [loading, setLoading] = useState(false);
  const [sending, setSending] = useState(false);
  const [testResultId, setTestResultId] = useState(null);
  const [editingCommentId, setEditingCommentId] = useState(null);
  const [editInputValue, setEditInputValue] = useState("");
  const [menuOpenId, setMenuOpenId] = useState(null);
  const messagesEndRef = useRef(null);

  const { user } = useAuth() || {};
  console.log("FE - raw user from useAuth:", user);
  const stompClientRef = useRef(null);

  // ROOM xác định theo itemType
  const roomId = itemType === "testOrder" ? itemId : testResultId;

  // ------------------ WEBSOCKET CONNECT ------------------
  const connectWebsocket = () => {
    if (!roomId) return;

    const socket = new SockJS(`${API_BASE}/ws`);
    const stomp = Stomp.over(socket);

    stomp.connect({}, () => {
      stomp.subscribe(`/topic/comments/${roomId}`, (msg) => {
        const event = JSON.parse(msg.body);

        if (event.type === "created") {
          setComments((prev) => [...prev, event.data]);
        }

        if (event.type === "updated") {
          setComments((prev) =>
            prev.map((c) => (c.id === event.data.id ? event.data : c))
          );
        }

        if (event.type === "deleted") {
          setComments((prev) => prev.filter((c) => c.id !== event.data.id));
        }
      });
    });

    stompClientRef.current = stomp;
  };

  const roleToDisplayName = (role) => {
    if (!role) return "Unknown";
    const r = role.toLowerCase();
    if (r.includes("manager")) return "Lab Manager";
    if (r.includes("tech")) return "Lab Technician";
    return "Unknown";
  };

  const getUserInfo = () => {
    const role = user?.roles?.[0] || "lab_tech";

    const userId =
      user?.id || // FE mapped ID
      user?.raw?.userId || // fallback
      null;

    return { role, userId };
  };

  const userInfo = getUserInfo();
  const roleLower = userInfo.role.toLowerCase();
  const canComment =
    roleLower.includes("manager") || roleLower.includes("tech");

  const callApi = async (endpoint, options = {}) => {
    const token = localStorage.getItem("lm.access");
    return axios({
      url: `${API_BASE}${endpoint}`,
      ...options,
      headers: {
        Authorization: token ? `Bearer ${token}` : undefined,
        "Content-Type": "application/json",
        ...options.headers,
      },
      withCredentials: true,
    });
  };

  // ------------------ LOAD COMMENTS ------------------
  const loadComments = async () => {
    if (!itemId) return;

    try {
      setLoading(true);
      setMenuOpenId(null);

      let commentsList = [];
      let resultId = null;

      if (itemType === "testOrder") {
        const response = await callApi(`/api/v1/test-orders/${itemId}`);
        commentsList = response.data.comments || [];
      } else if (itemType === "testResult") {
        const response = await callApi(
          `/api/v1/test-results/by-item/${itemId}`
        );
        const results = response.data;

        if (Array.isArray(results) && results.length > 0) {
          resultId = results[0].id;
          commentsList = results[0].comments || [];
        }
      }

      setComments(commentsList);
      setTestResultId(resultId);
      // eslint-disable-next-line no-unused-vars
    } catch (error) {
      Swal.fire("Error", "Failed to load comments", "error");
    } finally {
      setLoading(false);
    }
  };

  // ------------------ EFFECT: LOAD + CONNECT ------------------
  useEffect(() => {
    if (open && itemId) {
      loadComments();
    }
  }, [open, itemId, itemType]);

  useEffect(() => {
    if (!open) return;

    // khi testResultId được set xong → room valid → connect WS
    if (roomId) {
      connectWebsocket();
    }

    return () => {
      if (stompClientRef.current) {
        stompClientRef.current.disconnect();
      }
    };
  }, [roomId, open]);

  // ------------------ AUTO SCROLL ------------------
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [comments]);

  // ------------------ CREATE COMMENT ------------------
  const handleAddComment = async () => {
    if (!canComment) {
      Swal.fire(
        "Not allowed",
        "You don't have permission to comment.",
        "error"
      );
      return;
    }

    if (!inputValue.trim()) {
      Swal.fire("Warning", "Please enter a message", "warning");
      return;
    }

    try {
      setSending(true);

      const payload = { commentText: inputValue.trim() };

      if (itemType === "testOrder") payload.testOrderId = itemId;
      else if (itemType === "testResult") payload.testResultId = testResultId;

      await callApi("/api/v1/comments", {
        method: "POST",
        data: payload,
      });

      setInputValue("");
      onCommentAdded && onCommentAdded();
      // ❗KHÔNG loadComments → realtime WS sẽ tự update
    } catch (error) {
      Swal.fire(
        "Error",
        error.response?.data?.message || "Failed to add comment",
        "error"
      );
    } finally {
      setSending(false);
    }
  };

  // ------------------ EDIT & DELETE ------------------

  const handleEditComment = (comment) => {
    const createdById = comment.createdBy?.id;
    const canEdit = createdById === userInfo.userId;

    if (!createdById || !canEdit) {
      Swal.fire("Not allowed", "You can only edit your own messages.", "error");
      return;
    }

    setEditingCommentId(comment.id);
    setEditInputValue(comment.commentText);
    setMenuOpenId(null);
  };

  const handleSaveEdit = async () => {
    if (!editInputValue.trim()) {
      Swal.fire("Warning", "Please enter a message", "warning");
      return;
    }

    try {
      await callApi(`/api/v1/comments/${editingCommentId}`, {
        method: "PUT",
        data: {
          commentText: editInputValue.trim(),
        },
      });

      setEditingCommentId(null);
      setEditInputValue("");
      // ❗Realtime WebSocket update → không loadComments

      Swal.fire({
        toast: true,
        position: "top-end",
        timer: 2000,
        showConfirmButton: false,
        icon: "success",
        title: "Comment updated!",
      });
    } catch (error) {
      Swal.fire(
        "Error",
        error.response?.data?.message || "Failed to update comment",
        "error"
      );
    }
  };

  const handleDeleteComment = async (commentId, createdBy) => {
    const createdById = createdBy?.id;
    const canDelete = createdById === userInfo.userId;

    if (!createdById || !canDelete) {
      Swal.fire(
        "Not allowed",
        "You can only delete your own messages.",
        "error"
      );
      return;
    }

    const confirm = await Swal.fire({
      title: "Delete comment?",
      icon: "warning",
      showCancelButton: true,
      confirmButtonColor: "#ef4444",
    });

    if (!confirm.isConfirmed) return;

    try {
      await callApi(`/api/v1/comments/${commentId}`, { method: "DELETE" });
      // ❗Realtime sẽ tự remove comment
    } catch (error) {
      Swal.fire(
        "Error",
        error.response?.data?.message || "Failed to delete comment",
        "error"
      );
    }
  };

  const formatDateTime = (dateString) => {
    if (!dateString) return "";
    const date = new Date(dateString);
    return date.toLocaleString("en-US", {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 bg-black/30 backdrop-blur-sm flex justify-center items-center z-50">
      <div className="bg-white rounded-lg shadow-2xl w-full max-w-2xl h-96 flex flex-col">
        <div className="flex justify-between items-center p-4 border-b">
          <h2 className="text-xl font-semibold text-gray-800">
            💬 Comments & Discussion
          </h2>
          <button
            onClick={onClose}
            className="p-1 hover:bg-gray-100 rounded-md"
          >
            <X className="w-5 h-5 text-gray-500" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-3 bg-gray-50">
          {loading ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="w-6 h-6 animate-spin text-cyan-600" />
              <span className="ml-2 text-gray-600">Loading comments...</span>
            </div>
          ) : comments.length === 0 ? (
            <div className="text-center text-gray-400 py-8">
              No comments yet.
            </div>
          ) : (
            comments.map((comment) => {
              const createdBy = comment.createdBy || {};

              const isOwn = createdBy.id === userInfo.userId;

              console.log(
                "CHECK OWN:",
                "commentId =",
                comment.id,
                "| createdBy.id =",
                createdBy.id,
                "| currentUserId =",
                userInfo.userId,
                "| isOwn =",
                isOwn
              );

              // 🔥 GIỮ NGUYÊN BƯỚC G NHƯ YÊU CẦU
              const displayName =
                createdBy.displayName ||
                createdBy.username ||
                roleToDisplayName(createdBy.roles?.[0] || userInfo.role);

              const canShowActions = isOwn;

              return (
                <div
                  key={comment.id}
                  className={`flex items-start gap-1 ${
                    isOwn ? "justify-end" : "justify-start"
                  }`}
                >
                  {canShowActions && (
                    <div
                      className={`relative pt-2 ${
                        isOwn ? "order-last" : "order-first"
                      }`}
                    >
                      <button
                        onClick={() =>
                          setMenuOpenId(
                            menuOpenId === comment.id ? null : comment.id
                          )
                        }
                        className="p-1 text-gray-400 hover:bg-gray-200 rounded-full"
                      >
                        <MoreVertical className="w-4 h-4" />
                      </button>

                      {menuOpenId === comment.id && (
                        <div
                          className={`absolute ${
                            isOwn ? "right-0" : "left-0"
                          } top-10 bg-white border border-gray-200 rounded-lg shadow-lg w-32 z-10 overflow-hidden`}
                        >
                          <button
                            onClick={() => handleEditComment(comment)}
                            className="block w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-100"
                          >
                            Edit
                          </button>
                          <button
                            onClick={() =>
                              handleDeleteComment(comment.id, comment.createdBy)
                            }
                            className="block w-full text-left px-3 py-2 text-sm text-red-600 hover:bg-red-50"
                          >
                            Delete
                          </button>
                        </div>
                      )}
                    </div>
                  )}

                  {/* ---------- COMMENT BUBBLE ---------- */}
                  <div
                    className={`max-w-xs px-4 py-2 rounded-xl shadow-sm ${
                      isOwn
                        ? "bg-cyan-100 text-cyan-900 rounded-br-none"
                        : "bg-white text-gray-900 border border-gray-200 rounded-bl-none"
                    }`}
                  >
                    <div
                      className={isOwn ? "mb-1 text-right" : "mb-1 text-left"}
                    >
                      <p className="text-xs font-semibold">
                        {isOwn ? "You" : displayName}
                      </p>
                      <p className="text-xs text-gray-500">
                        {formatDateTime(comment.createdAt)}
                      </p>
                    </div>

                    {editingCommentId === comment.id ? (
                      <div className="mt-2 flex flex-col gap-2">
                        <textarea
                          value={editInputValue}
                          onChange={(e) => setEditInputValue(e.target.value)}
                          className="border rounded-lg p-2 text-sm w-full focus:ring-2 focus:ring-cyan-500 resize-none"
                          rows="2"
                        />
                        <div className="flex justify-end gap-2">
                          <button
                            onClick={handleSaveEdit}
                            disabled={!editInputValue.trim()}
                            className="px-3 py-1 text-xs bg-cyan-600 text-white rounded-lg hover:bg-cyan-700 disabled:opacity-50"
                          >
                            Save
                          </button>
                          <button
                            onClick={() => setEditingCommentId(null)}
                            className="px-3 py-1 text-xs bg-gray-200 text-gray-700 rounded-lg hover:bg-gray-300"
                          >
                            Cancel
                          </button>
                        </div>
                      </div>
                    ) : (
                      <p className="text-sm break-words">
                        {comment.commentText}
                      </p>
                    )}
                  </div>
                </div>
              );
            })
          )}

          <div ref={messagesEndRef} />
        </div>

        {/* ---------- INPUT ---------- */}
        <div className="border-t p-4 bg-white">
          <div className="flex gap-2">
            <input
              type="text"
              placeholder={
                canComment
                  ? "Type your message..."
                  : "You don't have permission to comment"
              }
              value={inputValue}
              onChange={(e) => setInputValue(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && !sending) handleAddComment();
              }}
              disabled={sending || !canComment || !!editingCommentId}
              className="flex-1 border rounded-lg px-3 py-2 text-sm focus:ring-2 focus:ring-cyan-500 disabled:bg-gray-100"
            />
            <button
              onClick={handleAddComment}
              disabled={
                sending ||
                !inputValue.trim() ||
                !canComment ||
                !!editingCommentId
              }
              className="px-4 py-2 bg-cyan-600 text-white rounded-lg hover:bg-cyan-700 disabled:opacity-50 flex items-center gap-2 text-sm"
            >
              {sending ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin" />
                  Sending...
                </>
              ) : (
                "Send"
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
