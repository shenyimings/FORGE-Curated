export const formatEVMObject = (object: {
  [key: string]: any;
}): (string | null)[] => {
  const result = Object.entries(object).map(ele => {
    // if (!isNaN(+ele[0])) return null;

    return `${ele[0]}: ${ele[1].toString()}`;
  });

  return result.filter(ele => ele !== null);
};

export const getRandomNumberBetween = (min: number, max: number): number => {
  return Math.floor(Math.random() * (max - min + 1) + min);
}
