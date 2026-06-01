import { createContext, ReactNode, useContext, useEffect, useMemo, useState } from "react";

import { api, TOKEN_STORAGE_KEY, USER_STORAGE_KEY } from "../api/client";
import { AuthResponse, User } from "../types";

interface AuthContextValue {
  token: string | null;
  user: User | null;
  isInitializing: boolean;
  login: (email: string, password: string) => Promise<void>;
  register: (name: string, email: string, password: string) => Promise<void>;
  logout: () => void;
  setUser: (user: User) => void;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

function readStoredUser(): User | null {
  const stored = localStorage.getItem(USER_STORAGE_KEY);
  if (!stored) {
    return null;
  }
  try {
    return JSON.parse(stored) as User;
  } catch {
    localStorage.removeItem(USER_STORAGE_KEY);
    return null;
  }
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [token, setTokenState] = useState<string | null>(() => localStorage.getItem(TOKEN_STORAGE_KEY));
  const [user, setUserState] = useState<User | null>(() => readStoredUser());
  const [isInitializing, setIsInitializing] = useState(true);

  const persistAuth = (payload: AuthResponse) => {
    localStorage.setItem(TOKEN_STORAGE_KEY, payload.access_token);
    localStorage.setItem(USER_STORAGE_KEY, JSON.stringify(payload.user));
    setTokenState(payload.access_token);
    setUserState(payload.user);
  };

  const clearAuth = () => {
    localStorage.removeItem(TOKEN_STORAGE_KEY);
    localStorage.removeItem(USER_STORAGE_KEY);
    setTokenState(null);
    setUserState(null);
  };

  useEffect(() => {
    async function validateStoredSession() {
      const storedToken = localStorage.getItem(TOKEN_STORAGE_KEY);
      if (!storedToken) {
        clearAuth();
        setIsInitializing(false);
        return;
      }

      try {
        const { data } = await api.get<User>("/users/profile");
        localStorage.setItem(USER_STORAGE_KEY, JSON.stringify(data));
        setTokenState(storedToken);
        setUserState(data);
      } catch {
        clearAuth();
      } finally {
        setIsInitializing(false);
      }
    }

    validateStoredSession();
  }, []);

  const value = useMemo<AuthContextValue>(
    () => ({
      token,
      user,
      isInitializing,
      login: async (email: string, password: string) => {
        const { data } = await api.post<AuthResponse>("/auth/login", { email, password });
        persistAuth(data);
      },
      register: async (name: string, email: string, password: string) => {
        const { data } = await api.post<AuthResponse>("/auth/register", { name, email, password });
        persistAuth(data);
      },
      logout: () => {
        clearAuth();
      },
      setUser: (nextUser: User) => {
        localStorage.setItem(USER_STORAGE_KEY, JSON.stringify(nextUser));
        setUserState(nextUser);
      }
    }),
    [isInitializing, token, user]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (!context) {
    throw new Error("useAuth must be used inside AuthProvider");
  }
  return context;
}
