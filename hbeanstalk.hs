import Data.Bits
import Network.Socket
import Network.BSD
import Data.List
import System.IO
import Text.ParserCombinators.Parsec
import Data.Yaml.Syck
import qualified Data.Map as M

type BeanstalkServer = Socket

connectBeanstalk :: HostName
                 -> String
                 -> IO BeanstalkServer
connectBeanstalk hostname port =
    do addrinfos <- getAddrInfo Nothing (Just hostname) (Just port)
       let serveraddr = head addrinfos
       -- Establish a socket for communication
       sock <- socket (addrFamily serveraddr) Stream defaultProtocol
       -- Mark the socket for keep-alive handling since it may be idle
       -- for long periods of time
       setSocketOption sock KeepAlive 1
       -- Connect to server
       connect sock (addrAddress serveraddr)
       return sock

getServerStats :: BeanstalkServer -> IO (M.Map String String)
getServerStats s =
    do send s "stats\r\n"
       statHeader <- readLine s
       let bytes = parseStatsLen statHeader
       (statContent, bytesRead) <- recvLen s bytes
       yamlN <- parseYaml statContent
       return $ yamlMapToHMap yamlN

printServerStats :: BeanstalkServer -> IO ()
printServerStats s =
    do stats <- getServerStats s
       let kv = M.assocs stats
       mapM_ (\(k,v) -> putStrLn (k ++ " => " ++ v)) kv

yamlMapToHMap :: YamlNode -> M.Map String String
yamlMapToHMap y = M.fromList elems where
    emap = (n_elem y)
    EMap maplist = emap -- [(YamlNode,YamlNode)]
    yelems = map (\(x,y) -> (n_elem x, n_elem y))  maplist
    elems = map (\(EStr x, EStr y) -> (unpackBuf x, unpackBuf y)) yelems

-- Read a single character from socket without handling errors
readChar :: Socket -> IO Char
readChar s = recv s 1 >>= return . head

-- Read up to and including a newline.  Any errors result in a string
-- starting with "Error: "
readLine :: Socket -> IO String
readLine s =
    catch readLine' (\err -> return ("Error: " ++ show err))
        where
          readLine' = do c <- readChar s
                         if c == '\n'
                           then return ""
                           else do l <- readLine s
                                   return (c:l)

parseStatsLen :: String -> Int
parseStatsLen input =
        case (parse statsLenParser "StatsLenParser" input) of
          Right len -> read len
          Left err -> 0



-- Parser for first line of stats for data length indicator
statsLenParser :: GenParser Char st String
statsLenParser = char 'O' >> char 'K' >> char ' ' >> many1 digit

-- Testing
main = do bs <- connectBeanstalk "localhost" "8887"
          printServerStats bs