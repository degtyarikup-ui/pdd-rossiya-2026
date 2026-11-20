// Keep retired purchase options verifiable for restores and renewals.
export const storeProducts = {
  appstore: {
    'u.pdd.pddApp.premium.week': 'weekly',
    'ru.pdd.pddApp.sub.3months': 'threeMonths',
    'ru.pdd.pddApp.sub.3months.v2': 'threeMonths',
    'ru.pdd.pddApp.sub.3months.trial3d': 'threeMonths',
    'ru.pdd.pddApp.sub.3months.trial3d.legacy': 'threeMonths',
  },
  googleplay: {
    'ru.pdd.pddapp.sub.week': 'weekly',
    'ru.pdd.pddapp.sub.3months': 'threeMonths',
    'ru.pdd.pddapp.sub.3months.v2': 'threeMonths',
    'ru.pdd.pddapp.sub.3months.trial3d': 'threeMonths',
    'ru.pdd.pddapp.sub.3months.trial3d.legacy': 'threeMonths',
  },
};

export function isTrialProduct(productId) {
  return (Object.hasOwn(storeProducts.appstore, productId) || Object.hasOwn(storeProducts.googleplay, productId)) &&
    (productId.endsWith('.trial3d') || productId.endsWith('.trial3d.legacy'));
}
