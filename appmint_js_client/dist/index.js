import { resolveConfig } from './config.js';
import { Transport } from './transport.js';
export { AppmintError, AppmintNetworkError } from './errors.js';
export class AppmintClient {
    t;
    constructor(config) {
        this.t = new Transport(resolveConfig(config));
    }
    /** Carry a signed-in visitor on subsequent calls. */
    setCustomerToken(token) { this.t.setCustomerToken(token); }
    /** Any endpoint, including ones with no helper below. */
    request = (method, path, body, query) => this.t.request(method, path, body, query);
    get = (path, query) => this.t.request('GET', path, undefined, query);
    post = (path, body, query) => this.t.request('POST', path, body, query);
    put = (path, body, query) => this.t.request('PUT', path, body, query);
    del = (path, query) => this.t.request('DELETE', path, undefined, query);
    products = {
        list: (query) => this.get('storefront/products', query),
        get: (slugOrSku) => this.get(`storefront/product/${encodeURIComponent(slugOrSku)}`),
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
        price: (input) => this.post('storefront/pricing/calculate-cart', input),
    };
    shipping = {
        options: (input) => this.post('shipping/options', input),
    };
    orders = {
        checkout: (input) => this.post('storefront/checkout-cart', input),
        get: (orderNumber) => this.get('storefront/order/get', { orderNumber }),
        mine: () => this.get('storefront/orders/get'),
        paymentGateways: () => this.get('storefront/payment-gateways'),
    };
    auth = {
        signIn: async (email, password) => {
            const res = await this.post('profile/customer/signin', { email, password });
            if (res?.token)
                this.setCustomerToken(res.token);
            return res;
        },
        signUp: (input) => this.post('profile/customer/signup', input),
        magicLink: (email) => this.get('profile/magic-link', { email }),
        profile: () => this.get('profile/customer/profile'),
    };
    affiliate = {
        /** Codes match case-insensitively. */
        resolve: (code) => this.get(`affiliate/public/resolve/${encodeURIComponent(code)}`),
        trackClick: (code, source = 'link') => this.post('affiliate/public/track', { code, source }),
        me: () => this.get('client/affiliate/me'),
    };
}
export const createClient = (config) => new AppmintClient(config);
