module HW.Worker
  ( worker
  )
where

import qualified CMark
import qualified Control.Concurrent
import qualified Control.Monad
import qualified Control.Monad.Trans.Reader
import qualified Data.Either
import qualified Data.IORef
import qualified Data.List.NonEmpty
import qualified Data.Map
import qualified Data.Set
import qualified HW.Handler.Issue
import qualified HW.Type.Article
import qualified HW.Type.Episode
import qualified HW.Type.Issue
import qualified HW.Type.Number
import qualified HW.Type.State
import qualified Network.URI

worker :: Data.IORef.IORef HW.Type.State.State -> IO ()
worker stateRef = do
  urls <- getUrls stateRef
  print $ Data.Set.size urls
  Control.Monad.forever $ Control.Concurrent.threadDelay 1000000

getUrls
  :: Data.IORef.IORef HW.Type.State.State -> IO (Data.Set.Set Network.URI.URI)
getUrls stateRef = do
  state <- Data.IORef.readIORef stateRef
  let urlsFromEpisodes = getUrlsFromEpisodes state
  urlsFromIssues <- getUrlsFromIssues stateRef
  pure . Data.Set.filter (not . shouldIgnore) $ Data.Set.union
    urlsFromEpisodes
    urlsFromIssues

getUrlsFromEpisodes :: HW.Type.State.State -> Data.Set.Set Network.URI.URI
getUrlsFromEpisodes =
  Data.Set.fromList
    . fmap HW.Type.Article.articleToUri
    . concatMap (Data.List.NonEmpty.toList . HW.Type.Episode.episodeArticles)
    . Data.Map.elems
    . HW.Type.State.stateEpisodes

getUrlsFromIssues
  :: Data.IORef.IORef HW.Type.State.State -> IO (Data.Set.Set Network.URI.URI)
getUrlsFromIssues stateRef = do
  state <- Data.IORef.readIORef stateRef
  fmap Data.Set.unions
    . mapM (getUrlsFromIssue stateRef . HW.Type.Issue.issueNumber)
    . Data.Map.elems
    $ HW.Type.State.stateIssues state

getUrlsFromIssue
  :: Data.IORef.IORef HW.Type.State.State
  -> HW.Type.Number.Number
  -> IO (Data.Set.Set Network.URI.URI)
getUrlsFromIssue stateRef number = do
  node <- Control.Monad.Trans.Reader.runReaderT
    (HW.Handler.Issue.readIssueFile number)
    stateRef
  pure
    . Data.Set.fromList
    . fmap HW.Type.Article.articleToUri
    . Data.Either.rights
    . fmap HW.Type.Article.textToArticle
    $ getUrlsFromNode node

getUrlsFromNode :: CMark.Node -> [CMark.Url]
getUrlsFromNode (CMark.Node _ nodeType nodes) =
  let rest = concatMap getUrlsFromNode nodes
  in
    case nodeType of
      CMark.LINK url _ -> url : rest
      _ -> rest

shouldIgnore :: Network.URI.URI -> Bool
shouldIgnore =
  maybe
      True
      (flip Data.Set.member domainNamesToIgnore . Network.URI.uriRegName)
    . Network.URI.uriAuthority

-- | These domains are frequently linked to, but they either don't have or
-- don't support Atom/RSS feeds. Instead of repeatedly discovering that, we'll
-- simply avoid crawling them at all.
domainNamesToIgnore :: Data.Set.Set String
domainNamesToIgnore = Data.Set.fromList
  [ "discourse.haskell.org"
  , "docs.google.com"
  , "ghc.haskell.org"
  , "gist.github.com"
  , "github.com"
  , "hackage.haskell.org"
  , "mail.haskell.org"
  , "medium.com" -- has RSS feeds, but not <link>ed
  , "np.reddit.com"
  , "stackoverflow.com"
  , "twitter.com"
  , "wiki.haskell.org"
  , "www.facebook.com"
  , "www.linkedin.com"
  , "www.meetup.com"
  , "www.youtube.com"
  ]