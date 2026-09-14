import { resolveConfig, type AppmintConfig } from './config.js';
import { Transport } from './transport.js';
import type {
  Address, BaseModel, CartItemInput, CartSummary, Paged, Product, ShippingOptionsResult,
} from './types.js';

export { AppmintError, AppmintNetworkError } from './errors.js';
export type { AppmintConfig } from './config.js';
export type * from './types.js';

export class AppmintClient {
  private readonly t: Transport;

  constructor(config: AppmintConfig) {
    this.t = new Transport(resolveConfig(config));
  }

  /** Carry a signed-in visitor on subsequent calls. */
  setCustomerToken(token: string | null) { this.t.setCustomerToken(token); }

  /** Any endpoint, including ones with no helper below. */
  request = <T = unknown>(method: string, path: string, body?: unknown, query?: Record<string, unknown>) =>
    this.t.request<T>(method, path, body, query);

  get = <T = unknown>(path: string, query?: Record<string, unknown>) => this.t.request<T>('GET', path, undefined, query);
  post = <T = unknown>(path: string, body?: unknown, query?: Record<string, unknown>) => this.t.request<T>('POST', path, body, query);
  put = <T = unknown>(path: string, body?: unknown, query?: Record<string, unknown>) => this.t.request<T>('PUT', path, body, query);
  del = <T = unknown>(path: string, query?: Record<string, unknown>) => this.t.request<T>('DELETE', path, undefined, query);

  products = {
    list: (query?: { p?: number; ps?: number; categories?: string; brand?: string; sort?: string }) =>
      this.get<Paged<Product>>('storefront/products', query),
    get: (slugOrSku: string) => this.get<BaseModel<Product>>(`storefront/product/${encodeURIComponent(slugOrSku)}`),
    categories: () => this.get('storefront/categories'),
    brands: () => this.get('storefront/brands'),
  };

  cart = {
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
    }) => this.post<CartSummary>('storefront/pricing/calculate-cart', input),
  };

  shipping = {
    options: (input: { items: Array<{ sku?: string; quantity: number }>; toAddress: Address; orderTotal?: number; discountCode?: string }) =>
      this.post<ShippingOptionsResult>('shipping/options', input),
  };

  orders = {
    checkout: (input: Record<string, unknown>) => this.post('storefront/checkout-cart', input),
    get: (orderNumber: string) => this.get('storefront/order/get', { orderNumber }),
    mine: () => this.get('storefront/orders/get'),
    paymentGateways: () => this.get('storefront/payment-gateways'),
  };

  auth = {
    signIn: async (email: string, password: string) => {
      const res = await this.post<{ token?: string }>('profile/customer/signin', { email, password });
      if (res?.token) this.setCustomerToken(res.token);
      return res;
    },
    signUp: (input: { email: string; firstName?: string; lastName?: string }) =>
      this.post('profile/customer/signup', input),
    magicLink: (email: string) => this.get('profile/magic-link', { email }),
    profile: () => this.get('profile/customer/profile'),
  };

  affiliate = {
    /** Codes match case-insensitively. */
    resolve: (code: string) => this.get(`affiliate/public/resolve/${encodeURIComponent(code)}`),
    trackClick: (code: string, source: 'link' | 'code' | 'qr' = 'link') =>
      this.post('affiliate/public/track', { code, source }),
    me: () => this.get('client/affiliate/me'),
  };
}

export const createClient = (config: AppmintConfig) => new AppmintClient(config);
