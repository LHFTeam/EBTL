import Cocktails, { additionalProductTypeOptions } from './Cocktails.jsx';

export default function AdditionalProducts() {
  return <Cocktails
    listApiPath="/api/additional-products"
    createApiPath="/api/additional-products"
    editApiPath="/api/cocktails"
    productType="snack"
    productTypeOptions={additionalProductTypeOptions}
    showProductTypeField
    showLiquorControls={false}
    labels={{
      addTitle: 'Add New Additional Product',
      addButton: 'Add product',
      namePlaceholder: 'Product name',
      imageTitle: 'Product image',
      imageHelp: 'Upload a 500px × 500px WebP image. The file will be stored in the Supabase cocktails bucket and linked to this product.',
      editImageHelp: 'Upload a replacement 500px × 500px WebP image. It will be saved to Supabase Storage and linked to this product.',
      saveCreateButton: 'Save Product',
      editTitle: 'Edit Additional Product',
      archiveButton: 'Archive product',
      archiveNoun: 'this product',
      entityName: 'Product',
      entityLower: 'product',
      tableTitle: 'Additional Products',
      emptyRecipeText: 'This product has no recipe yet. This is okay for drafts; create a recipe when you are ready to define inventory consumption.',
      replaceRecipeHelp: 'This editor replaces the full recipe item set for the product. Remove a line here, then save, to delete it from the recipe.',
      editVariantButton: 'Edit product',
      detailsUpdated: 'Product details updated.',
      archived: 'Product archived.',
      imageUploaded: 'Product image uploaded.',
      imageRemoved: 'Product image removed.',
      saved: 'Product saved.',
      savedWithImage: 'Product and image saved.',
      savedImageFailedPrefix: 'Product saved, but image upload failed'
    }}
  />;
}
