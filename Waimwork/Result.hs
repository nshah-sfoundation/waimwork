-- |An abort-like way to interrupt a wai application with an early result, in IO.
module Waimwork.Result
  ( result
  , unsafeResult
  , runResult
  , resultApplication
  , routeResultApplicationError
  , routeResultApplication
  , resultMiddleware
  ) where

import Control.Exception (Exception, throwIO, throw, handle)
import Control.Monad.IO.Class (MonadIO, liftIO)
import Data.Typeable (Typeable)
import Network.HTTP.Types.Header (ResponseHeaders)
import Network.HTTP.Types.Status (Status)
import Network.Wai (Middleware, Application, Request, Response, responseStatus, responseBuilder)
import Web.Route.Invertible (RouteMap)
import Web.Route.Invertible.Wai (routeWaiError)

newtype Result = Result { resultResponse :: Response } deriving (Typeable)
instance Show Result where
  showsPrec p (Result r) = showParen (p > 10)
    $ showString "Result " . showsPrec 11 (responseStatus r)
instance Exception Result

-- |Generate a result, aborting the rest of the computation.
-- Should only be called from within 'runResult' or 'resultMiddleware'.
result :: MonadIO m => Response -> m a
result = liftIO . throwIO . Result

-- |Generate a 'result' in pure code unsafely: it will only be used if evaluated.
unsafeResult :: Response -> a
unsafeResult = throw . Result

-- |Run a computation, catching any 'result' calls.
runResult :: IO Response -> IO Response
runResult = handle (return . resultResponse)

-- |Convert a simple function to an 'Application' using 'runResult'.
resultApplication :: (Request -> IO Response) -> Application
resultApplication = (.) ((>>=) . runResult)

-- |Combine 'Web.Route.Invertible.Wai.routeWaiError' with 'resultApplication'
routeResultApplicationError :: (Status -> ResponseHeaders -> Request -> IO Response) -> RouteMap (Request -> IO Response) -> Application
routeResultApplicationError e m = resultApplication $ routeWaiError e m

-- |Combine 'Web.Route.Invertible.Wai.routeWaiApplication' with 'resultApplication'
routeResultApplication :: RouteMap (Request -> IO Response) -> Application
routeResultApplication = routeResultApplicationError $ \s h _ -> return $ responseBuilder s h mempty

-- |Catch and send any 'result' generated from the application (regardless of whether a response has already been sent).
resultMiddleware :: Middleware
resultMiddleware app req send =
  handle
    (send . resultResponse)
    (app req send)
