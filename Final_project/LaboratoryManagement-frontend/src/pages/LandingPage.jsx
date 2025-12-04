import { useEffect, useState, createElement, useMemo } from "react";
import {
  Activity,
  Shield,
  Zap,
  Users,
  ArrowRight,
  Menu,
  X,
  LogOut,
} from "lucide-react";
import { useAuth } from "../lib";
import { Link, useNavigate } from "react-router-dom";

const TextType = ({
  text,
  as: Component = "div",
  typingSpeed = 50,
  initialDelay = 0,
  pauseDuration = 2000,
  deletingSpeed = 30,
  loop = true,
  className = "",
  showCursor = true,
  cursorCharacter = "|",
  textColors = [],
  ...props
}) => {
  const [displayedText, setDisplayedText] = useState("");
  const [currentCharIndex, setCurrentCharIndex] = useState(0);
  const [isDeleting, setIsDeleting] = useState(false);
  const [currentTextIndex, setCurrentTextIndex] = useState(0);

  const textArray = useMemo(
    () => (Array.isArray(text) ? text : [text]),
    [text]
  );

  const getCurrentTextColor = () => {
    if (textColors.length === 0) return "inherit";
    return textColors[currentTextIndex % textColors.length];
  };

  useEffect(() => {
    let timeout;
    const currentText = textArray[currentTextIndex] || "";

    const tick = () => {
      if (isDeleting) {
        if (displayedText.length > 0) {
          timeout = setTimeout(() => {
            setDisplayedText((prev) => prev.slice(0, -1));
          }, deletingSpeed);
        } else {
          setIsDeleting(false);
          if (currentTextIndex === textArray.length - 1 && !loop) return;
          timeout = setTimeout(() => {
            setCurrentTextIndex((prev) => (prev + 1) % textArray.length);
            setCurrentCharIndex(0);
          }, pauseDuration);
        }
      } else {
        if (currentCharIndex < currentText.length) {
          timeout = setTimeout(() => {
            setDisplayedText((prev) => prev + currentText[currentCharIndex]);
            setCurrentCharIndex((prev) => prev + 1);
          }, typingSpeed);
        } else if (textArray.length > 1) {
          timeout = setTimeout(() => setIsDeleting(true), pauseDuration);
        }
      }
    };

    if (currentCharIndex === 0 && !isDeleting && displayedText === "") {
      timeout = setTimeout(tick, initialDelay);
    } else {
      tick();
    }
    return () => clearTimeout(timeout);
  }, [
    currentCharIndex,
    displayedText,
    isDeleting,
    typingSpeed,
    deletingSpeed,
    pauseDuration,
    textArray,
    currentTextIndex,
    loop,
    initialDelay,
  ]);

  return createElement(
    Component,
    { className: `inline-block ${className}`, ...props },
    <span className="inline" style={{ color: getCurrentTextColor() }}>
      {displayedText}
    </span>,
    showCursor && (
      <span className="ml-1 inline-block animate-pulse">{cursorCharacter}</span>
    )
  );
};

export default function LandingPage() {
  const [isMenuOpen, setIsMenuOpen] = useState(false);
  const [signingOut, setSigningOut] = useState(false);
  const navigate = useNavigate();
  const { session, signOut } = useAuth();

  const handleGoMain = () => {
    navigate("/"); // route chính (dashboard)
  };

  const handleLogin = () => {
    navigate("/login");
  };

  const handleSignOut = async () => {
    try {
      setSigningOut(true);
      await signOut();
      setIsMenuOpen(false);
      navigate("/login", { replace: true });
    } catch (e) {
      console.error(e);
      alert("Đăng xuất thất bại!");
    } finally {
      setSigningOut(false);
    }
  };

  const features = [
    {
      icon: Activity,
      title: "Quản lý toàn diện",
      description:
        "Quản lý bệnh nhân, mẫu xét nghiệm và kết quả trên một nền tảng duy nhất",
    },
    {
      icon: Shield,
      title: "Bảo mật tuyệt đối",
      description:
        "Mã hóa dữ liệu end-to-end, đảm bảo thông tin y tế được bảo vệ an toàn",
    },
    {
      icon: Zap,
      title: "Nhanh chóng & Linh hoạt",
      description:
        "Truy cập mọi lúc mọi nơi, xử lý kết quả xét nghiệm trong thời gian thực",
    },
    {
      icon: Users,
      title: "Dễ dàng sử dụng",
      description:
        "Giao diện thân thiện, đào tạo nhanh chóng cho toàn bộ nhân viên",
    },
  ];
  const stats = [
    { value: "10,000+", label: "Xét nghiệm/tháng" },
    { value: "99.9%", label: "Uptime" },
    { value: "5,000+", label: "Bệnh nhân" },
    { value: "24/7", label: "Hỗ trợ" },
  ];

  return (
    <div className="min-h-screen bg-white">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 bg-white/80 backdrop-blur-lg border-b border-gray-200 z-50">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center space-x-2">
              <div className="w-10 h-10 bg-gradient-to-br from-blue-600 to-indigo-600 rounded-lg flex items-center justify-center">
                <Activity className="w-6 h-6 text-white" />
              </div>
              <span className="text-xl font-bold bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent">
                F-Laboratory Cloud
              </span>
            </div>

            {/* Desktop Menu */}
            <div className="hidden md:flex items-center space-x-8">
              <a
                href="#features"
                className="text-gray-700 hover:text-blue-600 transition font-medium"
              >
                Tính năng
              </a>
              <a
                href="#about"
                className="text-gray-700 hover:text-blue-600 transition font-medium"
              >
                Về chúng tôi
              </a>
              <a
                href="#contact"
                className="text-gray-700 hover:text-blue-600 transition font-medium"
              >
                Liên hệ
              </a>

              {session?.user ? (
                <div className="flex items-center space-x-3">
                  <span className="text-sm text-gray-600">
                    Xin chào,{" "}
                    <span className="font-semibold">
                      {session.user?.fullName || session.user?.username}
                    </span>
                  </span>

                  <button
                    onClick={handleGoMain}
                    className="px-4 py-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white rounded-lg hover:shadow-lg transition"
                  >
                    Vào trang chính
                  </button>

                  {/* Logout (DESKTOP) */}
                  <button
                    type="button"
                    onClick={handleSignOut}
                    disabled={signingOut}
                    className="p-2 text-gray-600 hover:text-red-600 hover:bg-red-50 rounded-lg transition border-2 border-transparent hover:border-red-200 disabled:opacity-50"
                    title="Đăng xuất"
                  >
                    <LogOut className="w-5 h-5" />
                  </button>
                </div>
              ) : (
                <button
                  onClick={handleLogin}
                  className="px-4 py-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white rounded-lg hover:shadow-lg transition"
                >
                  Đăng nhập
                </button>
              )}
            </div>

            {/* Mobile Menu Button */}
            <button
              className="md:hidden p-2 rounded-lg hover:bg-gray-100"
              onClick={() => setIsMenuOpen(!isMenuOpen)}
            >
              {isMenuOpen ? (
                <X className="w-6 h-6" />
              ) : (
                <Menu className="w-6 h-6" />
              )}
            </button>
          </div>
        </div>

        {/* Mobile Menu */}
        {isMenuOpen && (
          <div className="md:hidden border-t border-gray-200 bg-white">
            <div className="px-4 py-4 space-y-3">
              <a
                href="#features"
                className="block py-2 text-gray-700 hover:text-blue-600"
              >
                Tính năng
              </a>
              <a
                href="#about"
                className="block py-2 text-gray-700 hover:text-blue-600"
              >
                Về chúng tôi
              </a>
              <a
                href="#contact"
                className="block py-2 text-gray-700 hover:text-blue-600"
              >
                Liên hệ
              </a>

              {session?.user ? (
                <>
                  <div className="py-2 text-sm text-gray-600 border-t">
                    Xin chào,{" "}
                    <span className="font-semibold">
                      {session.user?.fullName || session.user?.username}
                    </span>
                  </div>

                  <button
                    onClick={handleGoMain}
                    className="block w-full px-4 py-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white rounded-lg text-center"
                  >
                    Vào trang chính
                  </button>

                  {/* Logout (MOBILE) */}
                  <button
                    type="button"
                    onClick={handleSignOut}
                    disabled={signingOut}
                    className="w-full px-4 py-3 bg-red-50 text-red-600 rounded-lg hover:bg-red-100 transition flex items-center justify-center space-x-2 font-semibold border-2 border-red-200 disabled:opacity-50"
                  >
                    <LogOut className="w-5 h-5" />
                    <span>
                      {signingOut ? "Đang đăng xuất..." : "Đăng xuất"}
                    </span>
                  </button>
                </>
              ) : (
                <button
                  onClick={handleLogin}
                  className="block w-full px-4 py-2 bg-gradient-to-r from-blue-600 to-indigo-600 text-white rounded-lg text-center"
                >
                  Đăng nhập
                </button>
              )}
            </div>
          </div>
        )}
      </nav>

      {/* Hero Section */}
      <section className="pt-32 pb-20 px-4 sm:px-6 lg:px-8 bg-gradient-to-br from-blue-50 via-white to-indigo-50">
        <div className="max-w-7xl mx-auto">
          <div className="text-center">
            <h1 className="text-5xl md:text-7xl font-bold text-gray-900 mb-6">
              <span className="bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent">
                F-Laboratory Cloud
              </span>
            </h1>

            <div className="text-2xl md:text-3xl text-gray-700 mb-8 h-20 flex items-center justify-center">
              <TextType
                text={[
                  "Một tài khoản — Quản lý toàn diện phòng xét nghiệm",
                  "Nhanh chóng, bảo mật và linh hoạt",
                  "Giải pháp số hóa cho phòng xét nghiệm hiện đại",
                ]}
                typingSpeed={75}
                pauseDuration={2000}
                showCursor={true}
                cursorCharacter="|"
                textColors={["#1e40af", "#4f46e5", "#059669"]}
              />
            </div>

            <p className="text-lg md:text-xl text-gray-600 mb-12 max-w-3xl mx-auto">
              Hệ thống quản lý phòng xét nghiệm toàn diện - Từ tiếp nhận mẫu, xử
              lý kết quả đến báo cáo phân tích. Tất cả trong một nền tảng duy
              nhất.
            </p>

            <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
              <button
                onClick={session?.user ? handleGoMain : handleLogin}
                className="group px-8 py-4 bg-gradient-to-r from-blue-600 to-indigo-600 text-white rounded-xl font-semibold hover:shadow-2xl transition transform hover:scale-105 flex items-center space-x-2"
              >
                <span>
                  {session?.user ? "Vào trang chính" : "Bắt đầu ngay"}
                </span>
                <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition" />
              </button>
              <Link
                to="/docs"
                className="px-8 py-4 bg-white text-gray-700 rounded-xl font-semibold border-2 border-gray-300 hover:border-blue-600 hover:text-blue-600 transition"
              >
                Tìm hiểu thêm
              </Link>
            </div>
          </div>

          {/* Stats */}
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 mt-20">
            {stats.map((stat, i) => (
              <div key={i} className="text-center">
                <div className="text-4xl font-bold bg-gradient-to-r from-blue-600 to-indigo-600 bg-clip-text text-transparent mb-2">
                  {stat.value}
                </div>
                <div className="text-gray-600">{stat.label}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Features */}
      <section id="features" className="py-20 px-4 sm:px-6 lg:px-8 bg-white">
        <div className="max-w-7xl mx-auto">
          <div className="text-center mb-16">
            <h2 className="text-4xl md:text-5xl font-bold text-gray-900 mb-4">
              Tính năng nổi bật
            </h2>
            <p className="text-xl text-gray-600 max-w-2xl mx-auto">
              Giải pháp toàn diện cho mọi nhu cầu quản lý phòng xét nghiệm
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
            {features.map((f, i) => (
              <div
                key={i}
                className="group p-8 bg-gradient-to-br from-gray-50 to-white rounded-2xl border border-gray-200 hover:border-blue-500 hover:shadow-xl transition duration-300"
              >
                <div className="w-14 h-14 bg-gradient-to-br from-blue-600 to-indigo-600 rounded-xl flex items-center justify-center mb-6 group-hover:scale-110 transition">
                  <f.icon className="w-7 h-7 text-white" />
                </div>
                <h3 className="text-xl font-bold text-gray-900 mb-3">
                  {f.title}
                </h3>
                <p className="text-gray-600">{f.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* CTA */}
      <section className="py-20 px-4 sm:px-6 lg:px-8 bg-gradient-to-br from-blue-600 via-indigo-600 to-purple-600">
        <div className="max-w-4xl mx-auto text-center text-white">
          <h2 className="text-4xl md:text-5xl font-bold mb-6">
            Sẵn sàng chuyển đổi số?
          </h2>
          <p className="text-xl mb-10 opacity-90">
            Tham gia cùng hàng trăm phòng xét nghiệm đã tin dùng F-Laboratory
            Cloud
          </p>
          <button
            onClick={session?.user ? handleGoMain : handleLogin}
            className="px-10 py-5 bg-white text-blue-600 rounded-xl font-bold text-lg hover:shadow-2xl transition transform hover:scale-105"
          >
            {session?.user ? "Vào trang chính" : "Đăng ký dùng thử miễn phí"}
          </button>
        </div>
      </section>

      {/* Footer */}
      <footer className="bg-gray-900 text-white py-12 px-4 sm:px-6 lg:px-8">
        <div className="max-w-7xl mx-auto">
          <div className="grid md:grid-cols-4 gap-8 mb-8">
            <div>
              <div className="flex items-center space-x-2 mb-4">
                <div className="w-8 h-8 bg-gradient-to-br from-blue-600 to-indigo-600 rounded-lg flex items-center justify-center">
                  <Activity className="w-5 h-5 text-white" />
                </div>
                <span className="font-bold text-lg">F-Laboratory</span>
              </div>
              <p className="text-gray-400 text-sm">
                Giải pháp số hóa cho phòng xét nghiệm hiện đại
              </p>
            </div>
            <div>
              <h4 className="font-semibold mb-4">Sản phẩm</h4>
              <ul className="space-y-2 text-gray-400 text-sm">
                <li>
                  <Link to="/features" className="hover:text-white transition">
                    Tính năng
                  </Link>
                </li>
                <li>
                  <Link to="/pricing" className="hover:text-white transition">
                    Bảng giá
                  </Link>
                </li>
                <li>
                  <Link to="/docs" className="hover:text-white transition">
                    Tài liệu
                  </Link>
                </li>
              </ul>
            </div>
            <div>
              <h4 className="font-semibold mb-4">Công ty</h4>
              <ul className="space-y-2 text-gray-400 text-sm">
                <li>
                  <Link to="/about" className="hover:text-white transition">
                    Về chúng tôi
                  </Link>
                </li>
                <li>
                  <Link to="/blog" className="hover:text-white transition">
                    Blog
                  </Link>
                </li>
                <li>
                  <Link to="/jobs" className="hover:text-white transition">
                    Careers
                  </Link>
                </li>
              </ul>
            </div>
            <div>
              <h4 className="font-semibold mb-4">Liên hệ</h4>
              <ul className="space-y-2 text-gray-400 text-sm">
                <li>Email: support@f-lab.vn</li>
                <li>Hotline: 1900 xxxx</li>
                <li>Địa chỉ: Cần Thơ, Việt Nam</li>
              </ul>
            </div>
          </div>
          <div className="border-t border-gray-800 pt-8 text-center text-gray-400 text-sm">
            <p>
              © {new Date().getFullYear()} F-Laboratory Cloud. All rights
              reserved.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
