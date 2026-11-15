/*

    ug-target - https://github.com/ugcore-project
    Copyright (C) 2026 UgCore Framework & Contributors
    Licensed under the GNU General Public License. See LICENSE for details.

*/

// Option icons by name. A fixed set keeps the bundle small: lucide names such as `car`, and Font Awesome classes
// from ox_target scripts (`fa-solid fa-car`), which map to the closest lucide icon. Unknown names get a dot.

import {
  Ambulance,
  Banknote,
  Box,
  Briefcase,
  Car,
  CarFront,
  Circle,
  CircleDot,
  Coffee,
  Cog,
  CreditCard,
  DoorOpen,
  Eye,
  Fish,
  Flame,
  Fuel,
  Gift,
  Hammer,
  Hand,
  Handshake,
  Heart,
  HeartPulse,
  House,
  IdCard,
  Info,
  Key,
  Lock,
  LockOpen,
  MessageCircle,
  Package,
  PenTool,
  Phone,
  Pill,
  Scissors,
  Search,
  Shield,
  ShoppingBag,
  ShoppingCart,
  Shirt,
  Siren,
  Skull,
  Store,
  Syringe,
  Trash2,
  Truck,
  User,
  Users,
  Utensils,
  Wrench,
  type LucideIcon,
} from "lucide-react";

const ICONS: Record<string, LucideIcon> = {
  ambulance: Ambulance,
  banknote: Banknote,
  money: Banknote,
  "money-bill": Banknote,
  "money-bill-wave": Banknote,
  box: Box,
  "box-open": Package,
  package: Package,
  briefcase: Briefcase,
  car: Car,
  "car-side": Car,
  "car-front": CarFront,
  circle: Circle,
  "circle-dot": CircleDot,
  coffee: Coffee,
  "mug-hot": Coffee,
  cog: Cog,
  gear: Cog,
  "credit-card": CreditCard,
  door: DoorOpen,
  "door-open": DoorOpen,
  eye: Eye,
  fish: Fish,
  fire: Flame,
  flame: Flame,
  fuel: Fuel,
  "gas-pump": Fuel,
  gift: Gift,
  hammer: Hammer,
  hand: Hand,
  "hand-holding": Hand,
  handshake: Handshake,
  heart: Heart,
  "heart-pulse": HeartPulse,
  "kit-medical": HeartPulse,
  house: House,
  home: House,
  "id-card": IdCard,
  info: Info,
  "circle-info": Info,
  key: Key,
  lock: Lock,
  "lock-open": LockOpen,
  unlock: LockOpen,
  "message-circle": MessageCircle,
  comment: MessageCircle,
  comments: MessageCircle,
  phone: Phone,
  pill: Pill,
  pills: Pill,
  scissors: Scissors,
  "pen-tool": PenTool,
  pen: PenTool,
  syringe: Syringe,
  search: Search,
  "magnifying-glass": Search,
  shield: Shield,
  "shield-halved": Shield,
  "shopping-bag": ShoppingBag,
  "bag-shopping": ShoppingBag,
  "shopping-cart": ShoppingCart,
  "cart-shopping": ShoppingCart,
  shirt: Shirt,
  "shirt-alt": Shirt,
  siren: Siren,
  "handcuffs": Siren,
  skull: Skull,
  store: Store,
  shop: Store,
  trash: Trash2,
  "trash-can": Trash2,
  truck: Truck,
  user: User,
  users: Users,
  "people-group": Users,
  utensils: Utensils,
  wrench: Wrench,
  screwdriver: Wrench,
  "screwdriver-wrench": Wrench,
};

const FA_STYLES = new Set(["fa", "fas", "far", "fab", "fa-solid", "fa-regular", "fa-brands", "fa-light", "fa-duotone", "fa-thin"]);

/** The icon for a name, or a dot. */
export function iconFor(name: string | undefined): LucideIcon {
  if (!name) {
    return CircleDot;
  }

  const tokens = name.trim().toLowerCase().split(/\s+/);

  for (const token of tokens) {
    if (FA_STYLES.has(token)) {
      continue;
    }

    const key = token.startsWith("fa-") ? token.slice(3) : token;
    const icon = ICONS[key];

    if (icon) {
      return icon;
    }
  }

  return CircleDot;
}

/** A color the page MAY use: hex or a CSS color name. Anything else is dropped. */
export function safeColor(value: string | undefined): string | undefined {
  if (!value) {
    return undefined;
  }

  return /^#[0-9a-f]{3,8}$/i.test(value) || /^[a-z]{3,20}$/i.test(value) ? value : undefined;
}
