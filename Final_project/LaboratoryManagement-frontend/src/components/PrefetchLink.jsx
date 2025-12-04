import React from "react";
import { NavLink } from "react-router-dom";
import componentMap from "../componentMap";

export default function PrefetchLink({ to, componentName, children, className, ...rest }) {
  const onMouseEnter = () => {
    try {
      const loader = componentMap[componentName];
      if (typeof loader === "function") loader();
    // eslint-disable-next-line no-unused-vars
    } catch (e) { /* empty */ }
  };

  return (
    <NavLink to={to} onMouseEnter={onMouseEnter} className={className} {...rest}>
      {children}
    </NavLink>
  );
}
