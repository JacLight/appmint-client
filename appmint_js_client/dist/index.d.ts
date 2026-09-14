import { type AppmintConfig } from './config.js';
import type { Address, BaseModel, CartItemInput, CartSummary, Paged, Product, ShippingOptionsResult } from './types.js';
export { AppmintError, AppmintNetworkError } from './errors.js';
export type { AppmintConfig } from './config.js';
export type * from './types.js';
export declare class AppmintClient {
    private readonly t;
    constructor(config: AppmintConfig);
    /** Carry a signed-in visitor on subsequent calls. */
    setCustomerToken(token: string | null): void;
    /** Any endpoint, including ones with no helper below. */
    request: <T = unknown>(method: string, path: string, body?: unknown, query?: Record<string, unknown>) => Promise<T>;
    get: <T = unknown>(path: string, query?: Record<string, unknown>) => Promise<T>;
    post: <T = unknown>(path: string, body?: unknown, query?: Record<string, unknown>) => Promise<T>;
    put: <T = unknown>(path: string, body?: unknown, query?: Record<string, unknown>) => Promise<T>;
    del: <T = unknown>(path: string, query?: Record<string, unknown>) => Promise<T>;
    products: {
        list: (query?: {
            p?: number;
            ps?: number;
            categories?: string;
            brand?: string;
            sort?: string;
        }) => Promise<Paged<Product>>;
        get: (slugOrSku: string) => Promise<BaseModel<Product>>;
        categories: () => Promise<unknown>;
        brands: () => Promise<unknown>;
    };
    cart: {
        /**
         * Price a cart — the only place money is decided.
         *
         * Send the coupon and destination WITH the items: the server nets the
         * discount, resolves shipping and computes tax in one pass. There is
         * deliberately no helper that adds the parts up.
         */
        price: (input: {
            productItems?: CartItemInput[];
            rentalItems?: CartItemInput[];
            shippingAddress?: Address;
            couponCode?: string;
            cartId?: string;
        }) => Promise<CartSummary>;
    };
    shipping: {
        options: (input: {
            items: Array<{
                sku?: string;
                quantity: number;
            }>;
            toAddress: Address;
            orderTotal?: number;
            discountCode?: string;
        }) => Promise<ShippingOptionsResult>;
    };
    orders: {
        checkout: (input: Record<string, unknown>) => Promise<unknown>;
        get: (orderNumber: string) => Promise<unknown>;
        mine: () => Promise<unknown>;
        paymentGateways: () => Promise<unknown>;
    };
    auth: {
        signIn: (email: string, password: string) => Promise<{
            token?: string;
        }>;
        signUp: (input: {
            email: string;
            firstName?: string;
            lastName?: string;
        }) => Promise<unknown>;
        magicLink: (email: string) => Promise<unknown>;
        profile: () => Promise<unknown>;
    };
    affiliate: {
        /** Codes match case-insensitively. */
        resolve: (code: string) => Promise<unknown>;
        trackClick: (code: string, source?: "link" | "code" | "qr") => Promise<unknown>;
        me: () => Promise<unknown>;
    };
}
export declare const createClient: (config: AppmintConfig) => AppmintClient;
