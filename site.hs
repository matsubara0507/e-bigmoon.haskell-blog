{-# LANGUAGE CPP               #-}
{-# LANGUAGE OverloadedStrings #-}

import qualified Config          as C
import           Data.List       (stripPrefix)
import           Data.Maybe
import           Data.Monoid     ((<>))
import           Hakyll

#if !(defined(mingw32_HOST_OS))
import           Hakyll.Web.Sass (sassCompiler)
#endif

main :: IO ()
main = do
  msiteConfig <- C.fromConfig "config.yml"
  maybe (error "Expected file 'config.yml' not found") main' msiteConfig

main' :: C.Site -> IO ()
main' siteConfig = hakyllWith hakyllConfig $ do
  match (fromGlob "images/**" .||. fromGlob "js/**" .||. fromGlob "lib/**") $ do
    route idRoute
    compile copyFileCompiler

#ifdef mingw32_HOST_OS
  match "css/*.css" $ do
    route idRoute
    compile compressCssCompiler
#else
  match "css/*.scss" $ do
    route $ setExtension "css"
    compile (fmap compressCss <$> sassCompiler)
#endif

-- TODO:watchで反映されない件byやまだ
  match (fromGlob "pages/**.md") $ do
    route
      $               customRoute
                        ( fromMaybe (error "Expected pages to be in 'pages' folder")
                        . stripPrefix "pages/"
                        . toFilePath
                        )
      `composeRoutes` setExtension "html"
    compile
      $   pandocCompiler
      >>= loadAndApplyTemplate "templates/page.html"    siteCtx
      >>= loadAndApplyTemplate "templates/default.html" siteCtx
      >>= relativizeUrls

  tags <- buildTags "posts/**" (fromCapture "tags/*.html")
  createTagsRules tags (\xs -> "Posts tagged \"" ++ xs ++ "\"")

  categories <- buildCategories "posts/**" (fromCapture "categories/*.html")
  createTagsRules categories (\xs -> "Posts categorised as \"" ++ xs ++ "\"")

  match "posts/**" $ do
    route $ setExtension "html"
    let namedTags = [("tags", tags), ("categories", categories)]
    compile
      $   pandocCompiler
      >>= saveSnapshot "content"
      >>= loadAndApplyTemplate "templates/post.html"
                               (ctxWithTags postCtx namedTags)
      >>= loadAndApplyTemplate "templates/default.html"
                               (ctxWithTags postCtx namedTags)
      >>= relativizeUrls

  create ["archive.html"] $ do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll "posts/*"
      let archiveCtx =
            listField "posts" postCtx (return posts)
              `mappend` constField "title" "Archives"
              `mappend` siteCtx
      makeItem ""
        >>= loadAndApplyTemplate "templates/archive.html" archiveCtx
        >>= loadAndApplyTemplate "templates/default.html" archiveCtx
        >>= relativizeUrls

  match "pages/index.html" $ do
    route (constRoute "index.html")
    compile $ do
      posts <- recentFirst =<< loadAll "posts/*"
      let indexCtx =
            listField "posts" postCtx (return posts)
              <> constField "title" "BIGMOON haskellers blog"
              <> siteCtx
      getResourceBody
        >>= applyAsTemplate indexCtx
        >>= loadAndApplyTemplate "templates/default.html" indexCtx
        >>= relativizeUrls

  match (fromGlob "partials/*" .||. fromGlob "templates/*")
    $ compile templateBodyCompiler

  create ["feed.xml"] $ do
    route idRoute
    compile $ do
      let feedConfig = C.feed siteConfig
          feedCtx    = postCtx <> bodyField "description"
      posts <- fmap (take 10) . recentFirst =<< loadAllSnapshots "posts/**"
                                                                 "content"
      renderAtom (atomFeedConfiguration feedConfig) feedCtx posts

  -- SEO-related stuff
  create ["sitemap.xml"] $ do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll "posts/**"
      pages <- loadAll "pages/*"
      let crawlPages = sitemapPages pages ++ posts

          sitemapCtx =
            mconcat [listField "entries" siteCtx (return crawlPages), siteCtx]
      makeItem ""
        >>= loadAndApplyTemplate "templates/sitemap.xml" sitemapCtx
        >>= relativizeUrls

  match "robots.txt" $ do
    route idRoute
    compile $ getResourceBody >>= relativizeUrls
 where
  ctxWithTags :: Context String -> [(String, Tags)] -> Context String
  ctxWithTags ctx =
    foldr (\(name, tags) baseCtx -> tagsField name tags <> baseCtx) ctx

  siteCtx :: Context String
  siteCtx = generalCtx <> styleCtx <> defaultContext
   where
    generalCtx =
      field "site-title" (toField C.general C.siteTitle)
        <> field "head-title" (toField C.general C.headTitle)
        <> field "base-url"   (toField C.general C.baseUrl)

    styleCtx =
      field "header-colour" (toField C.style C.headerColour)
        <> field "head-theme-colour"  (toField C.style C.headThemeColour)
        <> field "footer-colour"      (toField C.style C.footerColour)
        <> field "footer-btn-colour"  (toField C.style C.footerBtnColour)
        <> field "footer-link-colour" (toField C.style C.footerLinkColour)
        <> field "navbar-text-colour-desktop"
                 (toField C.style C.navbarTextColourDesktop)
        <> field "navbar-text-colour-mobile"
                 (toField C.style C.navbarTextColourMobile)

    toField configObj configField item = do
      _metadata <- getMetadata $ itemIdentifier item
      return $ configField (configObj siteConfig)

  postCtx :: Context String
  postCtx =
    dateField "date" "%B %e, %Y"
      <> teaserField "teaser" "content"
  -- create a short version of the teaser. Strip out HTML tags and trim.
      <> mapContext (trim' . take 160 . stripTags)
                    (teaserField "teaser-short" "content")
      <> siteCtx
   where
    trim' xs = map snd . filter trim'' $ zip [0 ..] xs
     where
      trim'' (ix, x)
        | ix == 0 || ix == (length xs - 1) = x `notElem` [' ', '\n', '\t']
        | otherwise                        = True

  createTagsRules :: Tags -> (String -> String) -> Rules ()
  createTagsRules tags mkTitle = tagsRules tags $ \tag pattern -> do
    route idRoute
    compile $ do
      posts <- recentFirst =<< loadAll pattern
      let ctx =
            constField "title" (mkTitle tag)
              <> listField "posts" postCtx (return posts)
              <> siteCtx

      makeItem ""
        >>= loadAndApplyTemplate "templates/tag.html"     ctx
        >>= loadAndApplyTemplate "templates/default.html" ctx
        >>= relativizeUrls

atomFeedConfiguration :: C.Feed -> FeedConfiguration
atomFeedConfiguration fs = FeedConfiguration
  { feedTitle       = C.title fs
  , feedDescription = C.description fs
  , feedAuthorName  = C.authorName fs
  , feedAuthorEmail = C.authorEmail fs
  , feedRoot        = C.root fs
  }

-- Friendlier config when using docker
hakyllConfig :: Configuration
hakyllConfig =
  defaultConfiguration { previewHost = "0.0.0.0", previewPort = 3001 }

sitemapPages :: [Item String] -> [Item String]
sitemapPages = filter ((/= "pages/LICENSE.md") . toFilePath . itemIdentifier)
